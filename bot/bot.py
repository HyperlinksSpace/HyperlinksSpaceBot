import os
import asyncio
import json
import re
import threading
from dotenv import load_dotenv
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, ContextTypes, CallbackQueryHandler, filters
from telegram.error import Conflict, TelegramError
import asyncpg
import httpx
from datetime import datetime, timezone

load_dotenv()

# Database connection pool
_db_pool = None
_message_prompt_map = {}
_stream_cancel_events: dict[tuple[int, int], threading.Event] = {}
_active_bot_msg_by_chat: dict[int, int] = {}

BASE_SYSTEM_PROMPT = (
    "You are a helpful assistant. Pay attention to the conversation history and respond "
    "appropriately to follow-up questions and confirmations."
)

LANGUAGE_SYSTEM_HINT = {
    "en": (
        "Respond only in English. Do not output JSON. "
        "Do not convert supply to USD. Supply is number of tokens. "
        "If decimals is null or unknown, say 'decimals unknown'."
    ),
    "ru": (
        "Respond only in Russian. Do not output JSON. "
        "Do not convert supply to USD. Supply is number of tokens. "
        "If decimals is null or unknown, say 'decimals unknown'."
    )
}

THINKING_TEXT = {
    "en": "Thinking...",
    "ru": "Думаю..."
}


def build_language_keyboard(message_id: int) -> InlineKeyboardMarkup:
    keyboard = [[
        InlineKeyboardButton("EN", callback_data=f"lang:en:{message_id}"),
        InlineKeyboardButton("RU", callback_data=f"lang:ru:{message_id}")
    ]]
    return InlineKeyboardMarkup(keyboard)


def cancel_stream(chat_id: int, message_id: int) -> None:
    event = _stream_cancel_events.get((chat_id, message_id))
    if event:
        event.set()


def _safe_int_like(value):
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return value


def sanitize_fact_value(value):
    if value is None:
        return "unknown"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).strip()
    text = text.replace("{", "").replace("}", "").replace("[", "").replace("]", "")
    text = text.replace('"', "").replace("`", "")
    return text if text else "unknown"


def build_regen_system_prompt(lang: str) -> str:
    return (
        f"{BASE_SYSTEM_PROMPT} {LANGUAGE_SYSTEM_HINT[lang]} "
        "Output plain text only. Never output JSON, code blocks, or key-value objects. "
        "Markdown bullet formatting is allowed. "
        "When token facts are present, keep this format exactly: "
        "Name, Symbol, Type; Total supply (tokens), Holders, Last activity; Sources (optional). "
        "Preserve numeric values exactly."
    )


def build_default_system_prompt(lang: str) -> str:
    language_line = "Respond only in Russian." if lang == "ru" else "Respond only in English."
    return f"{BASE_SYSTEM_PROMPT} {language_line}"


def detect_language_from_text(text: str, default: str = "en") -> str:
    if not text:
        return default
    cyrillic_count = sum(1 for ch in text if "\u0400" <= ch <= "\u04FF")
    latin_count = sum(1 for ch in text if ("a" <= ch.lower() <= "z"))
    if cyrillic_count > latin_count and cyrillic_count > 0:
        return "ru"
    if latin_count > 0:
        return "en"
    return default


def is_ticker_like_message(text: str) -> bool:
    value = (text or "").strip()
    if not value:
        return False
    lowered = value.lower()
    if "ticker" in lowered:
        return True
    if value.startswith("$") and len(value) <= 15:
        return True
    compact = re.sub(r"\s+", " ", value)
    if re.fullmatch(r"[A-Za-z0-9]{2,10}", compact):
        return True
    if re.fullmatch(r"(price|chart|info)\s+[A-Za-z0-9]{2,10}", lowered):
        return True
    return False


def get_last_user_message_from_history(history: list) -> str | None:
    for item in reversed(history):
        if item.get("role") == "user":
            content = (item.get("content") or "").strip()
            if content:
                return content
    return None


def format_token_facts_block(text: str) -> str | None:
    """Convert raw token JSON text into a compact human-readable facts block."""
    if not text:
        return None

    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None

    if isinstance(payload, dict) and isinstance(payload.get("token"), dict):
        payload = payload["token"]

    if not isinstance(payload, dict):
        return None

    name = sanitize_fact_value(payload.get("name"))
    symbol = sanitize_fact_value(payload.get("symbol"))
    token_type = sanitize_fact_value(payload.get("type") or payload.get("token_type"))
    total_supply = (
        payload.get("total_supply")
        or payload.get("supply")
        or payload.get("totalSupply")
    )
    holders = payload.get("holders") or payload.get("holder_count") or payload.get("holders_count")
    last_activity = (
        payload.get("last_activity")
        or payload.get("lastActivity")
        or payload.get("updated_at")
        or payload.get("updatedAt")
    )
    sources = payload.get("sources")

    lines = [
        f"Name: {name}",
        f"Symbol: {symbol}",
        f"Type: {token_type}",
        "",
        f"Total supply (tokens): {sanitize_fact_value(_safe_int_like(total_supply))}",
        f"Holders: {sanitize_fact_value(_safe_int_like(holders))}",
        f"Last activity: {sanitize_fact_value(last_activity)}",
    ]

    if isinstance(sources, list) and sources:
        source_text = ", ".join(sanitize_fact_value(item) for item in sources[:3])
        lines.extend(["", f"Sources: {source_text}"])
    elif isinstance(sources, str) and sources.strip():
        lines.extend(["", f"Sources: {sanitize_fact_value(sources)}"])

    return "\n".join(lines)


def looks_like_json(text: str) -> bool:
    value = text.strip()
    return (value.startswith("{") and value.endswith("}")) or (value.startswith("[") and value.endswith("]"))


def extract_fact_from_loose_text(text: str, keys: list[str]) -> str:
    if not text:
        return "unknown"
    lower_text = text.lower()
    for key in keys:
        idx = lower_text.find(key.lower())
        if idx == -1:
            continue
        suffix = text[idx + len(key):]
        if ":" in suffix[:3]:
            suffix = suffix[suffix.find(":") + 1:]
        elif "=" in suffix[:3]:
            suffix = suffix[suffix.find("=") + 1:]
        value = suffix.strip().splitlines()[0][:120]
        value = value.split(",")[0].strip()
        cleaned = sanitize_fact_value(value)
        if cleaned and cleaned != "unknown":
            return cleaned
    return "unknown"


def format_token_facts_block_from_loose_text(text: str) -> str | None:
    if not looks_like_json(text):
        return None

    name = extract_fact_from_loose_text(text, ["name"])
    symbol = extract_fact_from_loose_text(text, ["symbol", "ticker"])
    token_type = extract_fact_from_loose_text(text, ["type", "token_type"])
    total_supply = extract_fact_from_loose_text(text, ["total_supply", "totalSupply", "supply"])
    holders = extract_fact_from_loose_text(text, ["holders", "holder_count", "holders_count"])
    last_activity = extract_fact_from_loose_text(text, ["last_activity", "lastActivity", "updated_at", "updatedAt"])
    sources = extract_fact_from_loose_text(text, ["sources", "source"])

    lines = [
        f"Name: {name}",
        f"Symbol: {symbol}",
        f"Type: {token_type}",
        "",
        f"Total supply (tokens): {total_supply}",
        f"Holders: {holders}",
        f"Last activity: {last_activity}",
    ]
    if sources != "unknown":
        lines.extend(["", f"Sources: {sources}"])
    return "\n".join(lines)


async def get_db_pool():
    """Get or create database connection pool"""
    global _db_pool
    if _db_pool is None:
        database_url = os.getenv('DATABASE_URL')
        if not database_url:
            raise ValueError("DATABASE_URL environment variable is not set")
        
        # For local development on Windows, handle SSL certificate issues
        # In production (Railway), SSL will work fine
        import ssl
        
        try:
            # Try with SSL first (required for Neon)
            ssl_context = ssl.create_default_context()
            _db_pool = await asyncpg.create_pool(
                database_url,
                ssl=ssl_context
            )
        except Exception as e:
            # If SSL fails on Windows, try with relaxed SSL settings
            print(f"SSL connection failed with default context: {e}")
            print("Trying with relaxed SSL settings for local development...")
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            try:
                _db_pool = await asyncpg.create_pool(
                    database_url,
                    ssl=ssl_context
                )
            except Exception as e2:
                print(f"SSL connection failed even with relaxed settings: {e2}")
                raise
    return _db_pool


async def init_db():
    """Initialize database - create users and messages tables if they don't exist"""
    pool = await get_db_pool()
    async with pool.acquire() as conn:
        # Create users table
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                telegram_id BIGINT UNIQUE NOT NULL,
                username VARCHAR(255),
                first_name VARCHAR(255),
                last_name VARCHAR(255),
                language_code VARCHAR(10),
                created_at TIMESTAMP DEFAULT ((now() AT TIME ZONE 'UTC') + INTERVAL '3 hours'),
                updated_at TIMESTAMP DEFAULT ((now() AT TIME ZONE 'UTC') + INTERVAL '3 hours'),
                last_active_at TIMESTAMP DEFAULT ((now() AT TIME ZONE 'UTC') + INTERVAL '3 hours')
            )
        """)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id)
        """)
        
        # Create messages table for conversation history
        # Each user's messages are stored separately using telegram_id as the key
        # The composite index on (telegram_id, created_at) ensures efficient per-user history retrieval
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id SERIAL PRIMARY KEY,
                telegram_id BIGINT NOT NULL,
                role VARCHAR(20) NOT NULL CHECK (role IN ('system', 'user', 'assistant')),
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT ((now() AT TIME ZONE 'UTC') + INTERVAL '3 hours'),
                FOREIGN KEY (telegram_id) REFERENCES users(telegram_id) ON DELETE CASCADE
            )
        """)
        # Index for filtering messages by user (telegram_id)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_messages_telegram_id ON messages(telegram_id)
        """)
        # Composite index for efficient per-user history retrieval (ordered by timestamp)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(telegram_id, created_at ASC)
        """)
        print("Database initialized: users and messages tables created/verified")


async def save_user_async(update: Update):
    """Save or update user in database asynchronously (non-blocking)"""
    try:
        pool = await get_db_pool()
        user = update.effective_user
        
        async with pool.acquire() as conn:
            # Use PostgreSQL's INSERT ... ON CONFLICT for atomic upsert in ONE query
            # This is much faster than checking existence first
            # All timestamps use UTC+3 timezone (Moscow time)
            await conn.execute("""
                INSERT INTO users (telegram_id, username, first_name, last_name, language_code, last_active_at)
                VALUES ($1, $2, $3, $4, $5, (now() AT TIME ZONE 'UTC') + INTERVAL '3 hours')
                ON CONFLICT (telegram_id) 
                DO UPDATE SET 
                    username = EXCLUDED.username,
                    first_name = EXCLUDED.first_name,
                    last_name = EXCLUDED.last_name,
                    language_code = EXCLUDED.language_code,
                    last_active_at = (now() AT TIME ZONE 'UTC') + INTERVAL '3 hours',
                    updated_at = (now() AT TIME ZONE 'UTC') + INTERVAL '3 hours'
            """, 
                user.id,
                user.username,
                user.first_name,
                user.last_name,
                user.language_code
            )
    except Exception as e:
        print(f"Error saving user to database: {e}")


async def save_message(telegram_id: int, role: str, content: str):
    """
    Save a message to conversation history for a specific user
    Messages are stored separately per user using telegram_id as the key
    """
    try:
        pool = await get_db_pool()
        async with pool.acquire() as conn:
            await conn.execute("""
                INSERT INTO messages (telegram_id, role, content)
                VALUES ($1, $2, $3)
            """, telegram_id, role, content)
    except Exception as e:
        print(f"Error saving message to database: {e}")


async def get_conversation_history(telegram_id: int, limit: int = 5) -> list:
    """
    Retrieve conversation history for a specific user (separated by telegram_id)
    Each user's conversation is stored and fetched independently
    Returns list of dicts with 'role' and 'content' keys matching Ollama ChatMessage format
    """
    try:
        pool = await get_db_pool()
        async with pool.acquire() as conn:
            rows = await conn.fetch("""
                SELECT role, content
                FROM messages
                WHERE telegram_id = $1
                ORDER BY created_at ASC
                LIMIT $2
            """, telegram_id, limit)
            
            # Convert to list of dicts in Ollama ChatMessage format: {role, content}
            history = [
                {"role": row["role"], "content": row["content"]} 
                for row in rows
            ]
            return history
    except Exception as e:
        print(f"Error retrieving conversation history: {e}")
        return []


async def get_last_message_by_role(telegram_id: int, role: str) -> str | None:
    """Fetch latest message content for a user by role."""
    try:
        pool = await get_db_pool()
        async with pool.acquire() as conn:
            row = await conn.fetchrow("""
                SELECT content
                FROM messages
                WHERE telegram_id = $1 AND role = $2
                ORDER BY created_at DESC
                LIMIT 1
            """, telegram_id, role)
            return row["content"] if row else None
    except Exception as e:
        print(f"Error retrieving last {role} message: {e}")
        return None


async def ensure_user_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handler that ensures user exists in database (runs on all messages, non-blocking)"""
    # Run database operation asynchronously without blocking the response
    asyncio.create_task(save_user_async(update))
    # Don't return anything - let other handlers process the update


async def hello(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    # Create inline keyboard with button
    app_url = os.getenv('APP_URL')
    keyboard = [
        [InlineKeyboardButton("Run app", url=f"{app_url}?mode=fullscreen")]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(
        f"That's @HyperlinksSpaceBot, you can use AI in bot and explore the app for more features",
        reply_markup=reply_markup
    )


async def stream_ai_response(messages: list, bot, chat_id: int, message_id: int, telegram_id: int):
    """
    Stream AI response and edit message as chunks arrive
    messages: List of message dicts with 'role' and 'content' (Ollama ChatMessage format)
    """
    ai_backend_url = os.getenv('AI_BACKEND_URL')
    api_key = os.getenv('API_KEY')
    if not api_key:
        raise ValueError("API_KEY environment variable must be set")
    
    accumulated_text = ""
    last_edit_time = asyncio.get_event_loop().time()
    edit_interval = 1.0  # Edit message every 1 second to avoid rate limits
    last_sent_text = ""  # Track last sent text to avoid "message not modified" errors
    current_message_id = message_id
    key = (chat_id, message_id)
    tracked_keys = {key}
    cancel_event = threading.Event()
    _stream_cancel_events[key] = cancel_event

    async def edit_or_fallback_send(text: str):
        nonlocal current_message_id, last_sent_text, tracked_keys
        if not text or text == last_sent_text:
            return
        if cancel_event.is_set():
            return
        try:
            kwargs = {
                "chat_id": chat_id,
                "message_id": current_message_id,
                "text": text,
                "reply_markup": build_language_keyboard(current_message_id),
            }
            await bot.edit_message_text(**kwargs)
            last_sent_text = text
            return
        except TelegramError as e:
            if "not modified" in str(e).lower():
                return
            print(f"Warning: Could not edit message {current_message_id}: {e}. Falling back to send_message.")
        try:
            send_kwargs = {
                "chat_id": chat_id,
                "text": text,
                "reply_markup": build_language_keyboard(0),
            }
            sent = await bot.send_message(**send_kwargs)
            current_message_id = sent.message_id
            tracked_keys.add((chat_id, current_message_id))
            _stream_cancel_events[(chat_id, current_message_id)] = cancel_event
            _active_bot_msg_by_chat[chat_id] = current_message_id
            await bot.edit_message_reply_markup(
                chat_id=chat_id,
                message_id=current_message_id,
                reply_markup=build_language_keyboard(current_message_id)
            )
            last_sent_text = text
        except TelegramError as e:
            print(f"Warning: Could not send fallback message: {e}")
    
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            async with client.stream(
                "POST",
                f"{ai_backend_url}/api/chat",
                json={"messages": messages},  # Send messages array according to Ollama API spec
                headers={
                    "Content-Type": "application/json",
                    "X-API-Key": api_key
                }
            ) as response:
                response.raise_for_status()
                
                async for line in response.aiter_lines():
                    if cancel_event.is_set():
                        return
                    if line:
                        try:
                            data = json.loads(line)
                            if "error" in data:
                                error_text = f"Error: {data['error']}"
                                await edit_or_fallback_send(error_text)
                                return
                            
                            # Parse streaming response: token field contains partial content
                            if "token" in data:
                                accumulated_text += data["token"]
                            elif "response" in data:
                                accumulated_text = data["response"]
                            
                            # Edit message periodically to avoid rate limits (with signature)
                            current_time = asyncio.get_event_loop().time()
                            if current_time - last_edit_time >= edit_interval:
                                if cancel_event.is_set():
                                    return
                                signature = "\n\n***\n\nSincerely yours, @HyperlinksSpaceBot"
                                max_response_length = 4096 - len(signature)
                                if len(accumulated_text) > max_response_length:
                                    response_text = accumulated_text[:max_response_length - 3] + "..."
                                else:
                                    response_text = accumulated_text
                                
                                display_text = response_text + signature
                                if display_text and display_text != last_sent_text:
                                    await edit_or_fallback_send(display_text)
                                    last_edit_time = current_time
                            
                            if data.get("done", False):
                                break
                        except json.JSONDecodeError:
                            continue
                
                # Final edit with complete response (add signature)
                signature = "\n\n***\n\nSincerely yours, @HyperlinksSpaceBot"
                # Calculate available space for response (Telegram limit is 4096 chars)
                max_response_length = 4096 - len(signature)
                if len(accumulated_text) > max_response_length:
                    response_text = accumulated_text[:max_response_length - 3] + "..."
                else:
                    response_text = accumulated_text
                
                final_text = response_text + signature
                if cancel_event.is_set():
                    return
                
                await edit_or_fallback_send(final_text)
                
                # Save assistant response to conversation history (without signature for context)
                if accumulated_text:
                    asyncio.create_task(save_message(telegram_id, "assistant", accumulated_text))
                
                if not final_text:
                    no_response_text = "Sorry, I didn't receive a response."
                    await edit_or_fallback_send(no_response_text)
    except httpx.TimeoutException:
        error_text = "Sorry, the AI took too long to respond. Please try again."
        await edit_or_fallback_send(error_text)
    except httpx.RequestError as e:
        error_text = f"Sorry, I couldn't connect to the AI service. Error: {str(e)}"
        await edit_or_fallback_send(error_text)
    except Exception as e:
        error_text = f"Sorry, an error occurred: {str(e)}"
        await edit_or_fallback_send(error_text)
    finally:
        for key in list(tracked_keys):
            if _stream_cancel_events.get(key) is cancel_event:
                _stream_cancel_events.pop(key, None)
            if _active_bot_msg_by_chat.get(chat_id) == key[1]:
                _active_bot_msg_by_chat.pop(chat_id, None)


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle arbitrary text messages with AI responses"""
    if not update.message or not update.message.text:
        return
    
    message_text = update.message.text.strip()
    
    # Skip if message is empty or is a command
    if not message_text or message_text.startswith('/'):
        return
    
    telegram_id = update.effective_user.id
    chat_id = update.effective_chat.id
    prev_msg_id = _active_bot_msg_by_chat.get(chat_id)
    if prev_msg_id:
        cancel_stream(chat_id, prev_msg_id)
    
    # Retrieve conversation history (before saving current message)
    history = await get_conversation_history(telegram_id, limit=5)
    last_user_message = get_last_user_message_from_history(history)

    is_ticker_request = is_ticker_like_message(message_text)
    message_lang = detect_language_from_text(message_text)
    if is_ticker_request and last_user_message:
        message_lang = detect_language_from_text(last_user_message, default=message_lang)
    
    # Build messages array according to Ollama API spec
    messages = [{
        "role": "system",
        "content": build_default_system_prompt(message_lang)
    }]
    
    # Add conversation history
    messages.extend(history)
    
    # Add current user message
    user_message = {"role": "user", "content": message_text}
    messages.append(user_message)
    
    # Save user message to database (async, non-blocking)
    asyncio.create_task(save_message(telegram_id, "user", message_text))
    
    # Send initial "thinking" message
    sent_message = await update.message.reply_text(THINKING_TEXT.get(message_lang, THINKING_TEXT["en"]))
    _message_prompt_map[(sent_message.chat_id, sent_message.message_id)] = message_text
    _active_bot_msg_by_chat[sent_message.chat_id] = sent_message.message_id
    
    # Stream AI response and edit the message as chunks arrive
    await stream_ai_response(
        messages,
        context.bot,
        sent_message.chat_id,
        sent_message.message_id,
        telegram_id
    )


async def handle_language_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Regenerate response in selected language using original prompt when available."""
    query = update.callback_query
    if not query or not query.data:
        return

    parts = query.data.split(":", 2)
    if len(parts) != 3 or parts[0] != "lang":
        return

    lang = parts[1].lower()
    if lang not in LANGUAGE_SYSTEM_HINT:
        await query.answer("Unsupported language", show_alert=False)
        return

    try:
        target_message_id = int(parts[2])
    except ValueError:
        await query.answer("Invalid request", show_alert=False)
        return

    await query.answer("Generating...")

    if not query.message or not update.effective_user:
        return

    telegram_id = update.effective_user.id
    chat_id = query.message.chat_id
    cancel_stream(chat_id, target_message_id)

    thinking_text = THINKING_TEXT.get(lang, THINKING_TEXT["en"])
    active_message_id = target_message_id
    try:
        await context.bot.edit_message_text(
            chat_id=chat_id,
            message_id=target_message_id,
            text=thinking_text,
            reply_markup=build_language_keyboard(target_message_id)
        )
    except TelegramError as e:
        print(f"Warning: Could not edit callback target message {target_message_id}: {e}. Falling back to new message.")
        sent_message = await context.bot.send_message(chat_id=chat_id, text=thinking_text)
        active_message_id = sent_message.message_id
        try:
            await context.bot.edit_message_reply_markup(
                chat_id=chat_id,
                message_id=active_message_id,
                reply_markup=build_language_keyboard(active_message_id)
            )
        except TelegramError as e2:
            print(f"Warning: Could not attach keyboard to fallback message: {e2}")

    source_text = _message_prompt_map.get((chat_id, target_message_id))
    if not source_text:
        source_text = await get_last_message_by_role(telegram_id, "user")

    if not source_text:
        missing_text = "Sorry, I couldn't find text to regenerate."
        try:
            await context.bot.edit_message_text(
                chat_id=chat_id,
                message_id=active_message_id,
                text=missing_text,
                reply_markup=build_language_keyboard(active_message_id)
            )
        except TelegramError as e:
            print(f"Warning: Could not edit missing-source text: {e}. Sending fallback message.")
            missing_msg = await context.bot.send_message(chat_id=chat_id, text=missing_text)
            try:
                await context.bot.edit_message_reply_markup(
                    chat_id=chat_id,
                    message_id=missing_msg.message_id,
                    reply_markup=build_language_keyboard(missing_msg.message_id)
                )
            except TelegramError as e2:
                print(f"Warning: Could not attach keyboard to missing-source message: {e2}")
        return

    user_content = source_text

    messages = [
        {"role": "system", "content": build_regen_system_prompt(lang)},
        {"role": "user", "content": user_content}
    ]

    _message_prompt_map[(chat_id, active_message_id)] = source_text
    _active_bot_msg_by_chat[chat_id] = active_message_id

    await stream_ai_response(
        messages,
        context.bot,
        chat_id,
        active_message_id,
        telegram_id
    )


async def post_init(app):
    """Delete webhook and initialize database on startup"""
    # Delete webhook before starting polling to avoid conflicts
    try:
        await app.bot.delete_webhook(drop_pending_updates=True)
        print("Webhook deleted (if it existed)")
        # Small delay to ensure webhook deletion is processed
        await asyncio.sleep(1)
    except Exception as e:
        print(f"Note: Could not delete webhook: {e}")
    
    # Initialize database
    try:
        await init_db()
        print("Database connection established")
    except Exception as e:
        print(f"Warning: Could not initialize database: {e}")
        print("Bot will continue but user data won't be saved")


async def shutdown(app):
    """Close database pool on shutdown"""
    global _db_pool
    if _db_pool:
        await _db_pool.close()
        print("Database connection closed")


def main():
    bot_token = os.getenv('BOT_TOKEN')
    if not bot_token:
        raise ValueError("Environment variable 'BOT_TOKEN' is not set")
    
    app = ApplicationBuilder().token(bot_token).post_init(post_init).post_shutdown(shutdown).build()
    
    # Add handler to ensure user exists in DB on every message (non-blocking)
    # This runs first, before command handlers
    app.add_handler(MessageHandler(filters.ALL, ensure_user_handler), group=-1)
    
    # Add command handlers
    app.add_handler(CommandHandler("start", hello))
    app.add_handler(CallbackQueryHandler(handle_language_callback, pattern=r"^lang:(en|ru):\d+$"))
    
    # Add handler for arbitrary text messages (AI responses)
    # This should run after command handlers, so commands are processed first
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    
    print("Bot starting...")
    try:
        app.run_polling(drop_pending_updates=True, allowed_updates=Update.ALL_TYPES)
    except Conflict as e:
        print("Error: Another bot instance is already running or webhook conflict exists.")
        print("This usually resolves automatically. If it persists, check for other running instances.")
        print(f"Details: {e}")
        # Don't re-raise, just exit gracefully
        return
    except KeyboardInterrupt:
        print("\nBot stopped by user")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
