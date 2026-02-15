from __future__ import annotations
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any, Union, Literal, Tuple
import httpx
import os
import json
import re
import time
import asyncio
import urllib.parse
import logging
from pathlib import Path
from dotenv import load_dotenv

logger = logging.getLogger(__name__)
load_dotenv(Path(__file__).resolve().parent / ".env")

app = FastAPI()

# CORS middleware to allow Flutter app to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# LLM provider routing (default = Ollama)
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "ollama").strip().lower()
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:1.5b")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
RAG_URL = os.getenv("RAG_URL", "http://127.0.0.1:8001")
RESPONSE_FORMAT_VERSION = "facts_analysis_v2"

# ============================================================================
# TICKER DETECTION - PRODUCTION GRADE
# ============================================================================

# Regex for candidate extraction (alphanumeric 2-10 chars)
TICKER_RE = re.compile(r"\b[a-zA-Z0-9]{2,10}\b")

# Common non-ticker words to filter out (expand as needed)
COMMON_WORDS = {
    "THE", "WHAT", "THIS", "THAT", "HAVE", "WITH", "FROM", "THEY", "BEEN",
    "WERE", "SAID", "EACH", "WHICH", "THEIR", "ABOUT", "WOULD", "THESE",
    "OTHER", "COULD", "SOME", "THAN", "THEN", "THEM", "INTO", "ALSO",
    "YOUR", "JUST", "LIKE", "MORE", "VERY", "WHEN", "MAKE", "TIME",
    "YEAR", "OVER", "ONLY", "SUCH", "WELL", "BACK", "GOOD", "MUCH",
    "HTTP", "HTTPS", "WWW", "API", "URL", "COM", "ORG", "NET", "HTML",
    "JSON", "XML", "JPEG", "PNG", "GIF", "PDF", "DOC", "TXT", "CSV",
    "AND", "FOR", "ARE", "BUT", "NOT", "YOU", "ALL", "CAN", "HER",
    "WAS", "ONE", "OUR", "OUT", "DAY", "GET", "HAS", "HIM", "HIS",
    "HOW", "MAN", "NEW", "NOW", "OLD", "SEE", "TWO", "WAY", "WHO",
    "BOY", "DID", "ITS", "LET", "PUT", "SAY", "SHE", "TOO", "USE",
}

# Ticker context keywords (signals this is likely about crypto/tokens)
TICKER_CONTEXT_EN = {
    "token", "coin", "crypto", "price", "supply", "market", "cap",
    "contract", "address", "blockchain", "wallet", "exchange",
    "trading", "buy", "sell", "hodl", "moon", "lambo", "dip",
    "pump", "dump", "whale", "airdrop", "mint", "burn", "stake",
}

TICKER_CONTEXT_RU = {
    "токен", "монета", "крипто", "цена", "саплай", "капитализация",
    "контракт", "адрес", "блокчейн", "кошелёк", "биржа", "обмен",
    "торговля", "купить", "продать", "холдить", "луна", "памп",
    "дамп", "кит", "аирдроп", "минт", "сжигание", "стейкинг",
}

# Simple in-memory cache for ticker verification
# Format: {symbol: (is_valid: bool, data: dict|None, expires_at: float)}
_ticker_cache: Dict[str, Tuple[bool, Optional[dict], float]] = {}
CACHE_TTL_SECONDS = 600  # 10 minutes


def _is_cache_valid(symbol: str) -> bool:
    """Check if cached ticker data is still valid"""
    if symbol not in _ticker_cache:
        return False
    _, _, expires = _ticker_cache[symbol]
    return time.time() < expires


def _get_cached_ticker(symbol: str) -> Optional[Tuple[bool, Optional[dict]]]:
    """Get cached ticker validation result"""
    if not _is_cache_valid(symbol):
        return None
    is_valid, data, _ = _ticker_cache[symbol]
    return (is_valid, data)


def _cache_ticker(symbol: str, is_valid: bool, data: Optional[dict] = None):
    """Cache ticker validation result"""
    expires = time.time() + CACHE_TTL_SECONDS
    _ticker_cache[symbol] = (is_valid, data, expires)


def _extract_ticker_candidates(text: str) -> List[str]:
    """
    Extract and prioritize potential ticker symbols from text.
    Returns ordered list: uppercase + context-near candidates first.
    """
    if not text:
        return []
    
    # Extract all alphanumeric tokens
    raw_tokens = TICKER_RE.findall(text)
    if not raw_tokens:
        return []
    
    text_lower = text.lower()
    has_ticker_context = any(
        word in text_lower 
        for word in (TICKER_CONTEXT_EN | TICKER_CONTEXT_RU)
    )
    
    candidates = []
    seen = set()
    
    # Single-word queries like "dogs" should still be eligible as ticker intent.
    text_stripped = text.strip()
    normalized_tokens = [t.lower() for t in raw_tokens]

    # Phase 1: Prioritize obvious ticker patterns
    for token in raw_tokens:
        symbol = token.upper()
        
        # Skip if already seen
        if symbol in seen:
            continue
        
        # Filter: Skip all-digit tokens
        if symbol.isdigit():
            continue
        
        # Filter: Skip common words
        if symbol in COMMON_WORDS:
            continue
        
        has_dollar_signal = re.search(
            rf"\$\s*{re.escape(token)}\b",
            text,
            flags=re.IGNORECASE,
        ) is not None
        is_standalone_symbol_query = (
            len(raw_tokens) == 1
            and normalized_tokens[0] == token.lower()
            and text_stripped.lower() == token.lower()
        )

        # Filter: Skip mostly lowercase without context/symbol signal
        if token.islower() and not has_ticker_context and not has_dollar_signal and not is_standalone_symbol_query:
            continue
        
        # Filter: Skip very short tokens without uppercase or context
        if len(symbol) < 3 and not (token.isupper() or has_ticker_context):
            continue
        
        seen.add(symbol)
        
        # Priority scoring
        score = 0
        
        # +10: Preceded by $ (strong ticker signal)
        if f"${token}" in text or f"$ {token}" in text:
            score += 10
        
        # +5: All uppercase in original text
        if token.isupper():
            score += 5
        
        # +3: Has uppercase letter(s)
        elif any(c.isupper() for c in token):
            score += 3
        
        # +2: Near ticker context words
        if has_ticker_context:
            score += 2
        
        # +1: Wrapped in punctuation (e.g., "DOGS?" or "(MCOM)")
        if any(f"{p}{token}{q}" in text for p in "([{\"'" for q in ")]}\"'?!.,;"):
            score += 1
        
        candidates.append((score, symbol))
    
    # Sort by score (descending), then alphabetically
    candidates.sort(key=lambda x: (-x[0], x[1]))
    
    # Return top 8 candidates max (prevent RAG spam)
    return [sym for _, sym in candidates[:8]]


async def detect_ticker_via_rag(
    user_text: str, 
    rag_url: str, 
    timeout_s: float = 2.0,
    max_retries: int = 2,
    retry_delay_s: float = 0.2,
) -> Tuple[Optional[str], Optional[dict], Optional[str]]:
    """
    Detect and verify ticker symbol via RAG service.
    
    Returns:
        (ticker_symbol, ticker_data, error_code)
        
        error_code can be:
        - None: Success, valid ticker found
        - "not_found": No valid ticker found in RAG
        - "timeout": RAG service timeout
        - "unavailable": RAG service error
    """
    candidates = _extract_ticker_candidates(user_text)
    
    if not candidates:
        return None, None, "not_found"
    
    async with httpx.AsyncClient(timeout=timeout_s) as client:
        for symbol in candidates:
            # Check cache first
            cached = _get_cached_ticker(symbol)
            if cached is not None:
                is_valid, data = cached
                if is_valid:
                    return symbol, data, None
                continue  # Try next candidate if this one is cached as invalid
            
            # Verify via RAG
            last_transport_error = None
            r = None
            for attempt in range(max_retries + 1):
                try:
                    r = await client.get(f"{rag_url.rstrip('/')}/tokens/{symbol}")
                    last_transport_error = None
                    break
                except (httpx.TimeoutException, httpx.RequestError) as e:
                    last_transport_error = e
                    if attempt < max_retries:
                        await asyncio.sleep(retry_delay_s)
                        continue
                    r = None
                    break

            if r is None:
                if isinstance(last_transport_error, httpx.TimeoutException):
                    return None, None, "timeout"
                return None, None, "unavailable"
            
            try:
                
                # 404 = not a valid ticker, cache and continue
                if r.status_code == 404:
                    _cache_ticker(symbol, False)
                    continue
                
                # 5xx = upstream issue, do not mark ticker invalid
                if r.status_code >= 500:
                    logger.warning(f"RAG upstream error for {symbol}: status={r.status_code}")
                    return None, None, "unavailable"
                
                # Success
                if r.status_code == 200:
                    try:
                        data = r.json()
                        
                        # Validate response structure
                        if not isinstance(data, dict):
                            logger.warning(f"RAG returned non-dict payload for {symbol}")
                            return None, None, "unavailable"
                        
                        # Check for error field
                        if data.get("error"):
                            # Do not negative-cache generic upstream errors
                            err_text = str(data.get("error", "")).lower()
                            if "not found" in err_text or "ticker not found" in err_text:
                                _cache_ticker(symbol, False)
                            continue
                        
                        # Valid ticker found - cache and return
                        _cache_ticker(symbol, True, data)
                        return symbol, data, None
                    
                    except (json.JSONDecodeError, ValueError):
                        # Malformed response from upstream - do not mark ticker invalid
                        logger.warning(f"RAG returned malformed JSON for {symbol}")
                        return None, None, "unavailable"
                
                # Other non-200 codes: try next candidate, no negative cache.
                
            except Exception as e:
                # Other errors - log and continue to next candidate
                logger.warning(f"RAG verification failed for {symbol}: {e}")
                continue
    
    # No valid ticker found in any candidate
    return None, None, "not_found"


def _detect_language(text: str) -> str:
    """Detect if text is primarily Russian or English"""
    if not text:
        return "en"
    
    # Count Cyrillic characters
    cyrillic_count = sum(1 for c in text if '\u0400' <= c <= '\u04FF')
    total_alpha = sum(1 for c in text if c.isalpha())
    
    if total_alpha == 0:
        return "en"
    
    # If >30% Cyrillic, consider it Russian
    return "ru" if (cyrillic_count / total_alpha) > 0.3 else "en"


def _to_int(value: Any) -> Optional[int]:
    """Best-effort conversion of ticker numeric fields to int."""
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        cleaned = re.sub(r"[,_\s]", "", value.strip())
        if cleaned.isdigit():
            return int(cleaned)
    return None


def _format_int_with_commas(value: Optional[int]) -> Optional[str]:
    if value is None:
        return None
    return f"{value:,}"


def _format_compact_number(value: Optional[int]) -> Optional[str]:
    """Compact formatter like 545.2Q for very large values."""
    if value is None:
        return None
    
    scales = [
        (10**18, "Qi"),  # Quintillion (10^18)
        (10**15, "Q"),   # Quadrillion (10^15)
        (10**12, "T"),   # Trillion
        (10**9, "B"),    # Billion
        (10**6, "M"),    # Million
        (10**3, "K"),    # Thousand
    ]
    for threshold, suffix in scales:
        if value >= threshold:
            return f"{value / threshold:.1f}{suffix}"
    return str(value)


def _metric_display(value: Any) -> Optional[str]:
    parsed = _to_int(value)
    if parsed is not None:
        return _format_int_with_commas(parsed)
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _format_activity_date(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if len(text) >= 10 and text[4] == "-" and text[7] == "-":
        return text[:10]
    return text


def _resolve_token_source(ticker_data: Dict[str, Any]) -> str:
    source = ticker_data.get("source")
    if source:
        return str(source)
    sources = ticker_data.get("sources")
    if isinstance(sources, list):
        for item in sources:
            if isinstance(item, dict) and item.get("source_name"):
                return str(item["source_name"])
    return "tokens.swap.coffee"


def _build_ticker_facts_block(ticker_data: Dict[str, Any], ticker_symbol: Optional[str], user_lang: str) -> str:
    symbol = str(ticker_data.get("symbol") or ticker_symbol or "Unknown")
    name = str(ticker_data.get("name") or symbol)
    token_type = str(ticker_data.get("type") or "token").lower()
    is_jetton = token_type == "jetton"

    # RAW VALUES - exactly as fetched
    supply_raw = ticker_data.get("total_supply")
    holders_raw = ticker_data.get("holders")
    
    # Format raw integers with commas for readability (but keep them accurate)
    supply_display = _metric_display(supply_raw) if supply_raw is not None else None
    holders_display = _metric_display(holders_raw) if holders_raw is not None else None
    
    last_activity_value = _format_activity_date(ticker_data.get("last_activity"))
    source_value = _resolve_token_source(ticker_data)

    if user_lang == "ru":
        type_text = "джеттон" if is_jetton else "токен"
        
        lines = [
            f"🪙 {name}",
            "",
            f"{type_text.capitalize()} в сети TON",
            f"Выпуск: {supply_display if supply_display else 'неизвестно'}",
            f"Держатели: {holders_display if holders_display else 'неизвестно'}",
            f"Последняя активность: {last_activity_value if last_activity_value else 'неизвестно'}",
            "",
            f"ℹ️ Источник: {source_value}"
        ]
        
    else:
        type_text = "jetton" if is_jetton else "token"
        
        lines = [
            f"🪙 {name}",
            "",
            f"{type_text.capitalize()} on TON",
            f"Supply: {supply_display if supply_display else 'not available'}",
            f"Holders: {holders_display if holders_display else 'not available'}",
            f"Last activity: {last_activity_value if last_activity_value else 'not available'}",
            "",
            f"ℹ️ Source: {source_value}"
        ]
    
    return "\n".join(lines)


_CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")


def _narrative_fallback(user_lang: str) -> str:
    return "Недостаточно данных для анализа." if user_lang == "ru" else "Insufficient data for analysis."


def _sanitize_ticker_narrative(narrative: str, user_lang: str) -> str:
    text = (narrative or "").strip()
    if not text:
        return _narrative_fallback(user_lang)
    # Guardrail: block metric restatements and mixed-script garbage.
    if re.search(r"\d", text) or _CJK_RE.search(text):
        return _narrative_fallback(user_lang)
    return text


def _build_deterministic_ticker_overview(ticker_data: Dict[str, Any], user_lang: str) -> str:
    token_type = str(ticker_data.get("type") or "token").lower()
    is_jetton = token_type == "jetton"
    if user_lang == "ru":
        first = "Это джеттон в экосистеме TON." if is_jetton else "Это токен в экосистеме TON."
        second = "Обзор сформирован только по подтверждённым данным выше, без дополнительных предположений."
        return f"{first} {second}"
    first = "This is a TON ecosystem jetton." if is_jetton else "This is a TON ecosystem token."
    second = "This overview is based only on the verified data shown above, with no additional assumptions."
    return f"{first} {second}"


def _is_ticker_context_strong(text: str) -> bool:
    """
    Check if message has strong ticker/crypto context signals.
    This helps distinguish:
    - "DOGS token price" (strong) vs "I love dogs" (weak)
    - "что такое DOGS токен" (strong) vs "что такое dogs" (weak)
    """
    if not text:
        return False
    
    text_lower = text.lower()
    
    # Strong signals
    if "$" in text:
        return True
    
    # Uppercase ticker-like token is also a strong signal (e.g., "что такое DOGS")
    if re.search(r"\b[A-Z0-9]{3,10}\b", text):
        return True
    
    # Context words alone are not enough, they create false positives.
    # Keep this helper strict: only explicit ticker/symbol clues count.
    return False


def _has_explicit_ticker_signal(text: str) -> bool:
    """
    Return True only when the user message contains an explicit ticker-like cue.
    This prevents generic prompts (e.g., wallet/profit questions) from being
    misrouted into ticker mode.
    """
    if not text:
        return False

    text_lower = text.lower()

    # Strong universal signals
    if "$" in text:
        return True
    if re.search(r"\b[A-Z0-9]{3,10}\b", text):
        return True

    # Single standalone token symbol: e.g., "dogs"
    text_stripped = text.strip()
    one_token = re.fullmatch(r"[a-zA-Z0-9]{2,10}", text_stripped)
    if one_token:
        symbol = text_stripped.upper()
        if not symbol.isdigit() and symbol not in COMMON_WORDS:
            return True

    # English explicit forms: "dogs token", "token dogs", "ticker dogs"
    if re.search(r"\b[a-z0-9]{2,10}\s+(token|coin|jetton|ticker)\b", text_lower):
        return True
    if re.search(r"\b(token|coin|jetton|ticker)\s+[a-z0-9]{2,10}\b", text_lower):
        return True

    # Russian explicit forms: "dogs токен", "токен dogs", etc.
    if re.search(r"\b[a-z0-9]{2,10}\s+(токен|монета|тикер|джеттон)\b", text_lower):
        return True
    if re.search(r"\b(токен|монета|тикер|джеттон)\s+[a-z0-9]{2,10}\b", text_lower):
        return True

    return False


# ============================================================================
# API KEY VERIFICATION
# ============================================================================

API_KEY = os.getenv("API_KEY")


def verify_api_key(x_api_key: Optional[str] = Header(None, alias="X-API-Key")):
    """
    Verify API key from X-API-Key header
    """
    if not API_KEY:
        raise HTTPException(
            status_code=503,
            detail="API key authentication is not configured on this deployment.",
        )
    if not x_api_key:
        raise HTTPException(
            status_code=401,
            detail="API key required. Please provide X-API-Key header."
        )
    if x_api_key != API_KEY:
        raise HTTPException(
            status_code=403,
            detail="Invalid API key"
        )
    return x_api_key


# ============================================================================
# PYDANTIC MODELS
# ============================================================================

class ChatMessage(BaseModel):
    """Individual chat message following Ollama ChatMessage format"""
    role: Literal["system", "user", "assistant", "tool"] = Field(..., description="Author of the message")
    content: str = Field(..., description="Message text content")
    images: Optional[List[str]] = Field(default=None, description="Optional list of inline images for multimodal models")
    tool_calls: Optional[List[Dict[str, Any]]] = Field(default=None, description="Tool call requests produced by the model")


class ModelOptions(BaseModel):
    """Runtime options that control text generation"""
    seed: Optional[int] = None
    temperature: Optional[float] = None
    top_k: Optional[int] = None
    top_p: Optional[float] = None
    min_p: Optional[float] = None
    stop: Optional[Union[str, List[str]]] = None
    num_ctx: Optional[int] = None
    num_predict: Optional[int] = None
    num_thread: Optional[int] = None  # Custom field for backward compatibility


class ChatRequest(BaseModel):
    """Chat request following Ollama API spec"""
    model: Optional[str] = Field(default=None, description="Model name (uses provider default env var if not provided)")
    messages: List[ChatMessage] = Field(..., description="Chat history as an array of message objects")
    tools: Optional[List[Dict[str, Any]]] = Field(default=None, description="Optional list of function tools the model may call")
    format: Optional[Union[str, Dict[str, Any]]] = Field(default=None, description="Format to return a response in. Can be 'json' or a JSON schema")
    options: Optional[ModelOptions] = Field(default=None, description="Runtime options that control text generation")
    stream: bool = Field(default=True, description="Enable streaming response")
    think: Optional[Union[bool, str]] = Field(default=None, description="When true, returns separate thinking output. Can be boolean or 'high', 'medium', 'low'")
    keep_alive: Optional[Union[str, int]] = Field(default=None, description="Model keep-alive duration (e.g., '5m' or 0)")
    logprobs: Optional[bool] = Field(default=None, description="Whether to return log probabilities of the output tokens")
    top_logprobs: Optional[int] = Field(default=None, description="Number of most likely tokens to return at each token position when logprobs are enabled")


# ============================================================================
# API ENDPOINTS
# ============================================================================

@app.get("/")
async def root():
    return {
        "status": "ok",
        "message": "AI Chat API is running",
        "response_format_version": RESPONSE_FORMAT_VERSION,
    }


def _normalize_provider() -> str:
    if LLM_PROVIDER == "openai":
        return "openai"
    return "ollama"


async def _check_rag_health(timeout_s: float = 2.0) -> Dict[str, Any]:
    if not RAG_URL:
        return {
            "status": "skipped",
            "configured": False,
            "reason": "RAG_URL is not set",
        }

    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(timeout=timeout_s) as client:
            r = await client.get(f"{RAG_URL.rstrip('/')}/health")
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        if r.status_code == 200:
            return {
                "status": "ok",
                "configured": True,
                "url": RAG_URL,
                "latency_ms": elapsed_ms,
                "status_code": 200,
            }
        return {
            "status": "error",
            "configured": True,
            "url": RAG_URL,
            "latency_ms": elapsed_ms,
            "status_code": r.status_code,
            "error": f"Unexpected status from RAG health endpoint: {r.status_code}",
        }
    except Exception as e:
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return {
            "status": "error",
            "configured": True,
            "url": RAG_URL,
            "latency_ms": elapsed_ms,
            "error": str(e),
        }


async def _check_llm_health(provider: str, timeout_s: float = 2.0) -> Dict[str, Any]:
    started = time.perf_counter()

    if provider == "openai":
        if not OPENAI_API_KEY:
            return {
                "status": "error",
                "provider": "openai",
                "model": OPENAI_MODEL,
                "configured": False,
                "error": "OPENAI_API_KEY is missing",
            }

        try:
            async with httpx.AsyncClient(timeout=timeout_s) as client:
                r = await client.get(
                    f"https://api.openai.com/v1/models/{OPENAI_MODEL}",
                    headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                )
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            if r.status_code == 200:
                return {
                    "status": "ok",
                    "provider": "openai",
                    "model": OPENAI_MODEL,
                    "configured": True,
                    "latency_ms": elapsed_ms,
                    "status_code": 200,
                }
            return {
                "status": "error",
                "provider": "openai",
                "model": OPENAI_MODEL,
                "configured": True,
                "latency_ms": elapsed_ms,
                "status_code": r.status_code,
                "error": f"OpenAI model check failed: {r.status_code}",
            }
        except Exception as e:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            return {
                "status": "error",
                "provider": "openai",
                "model": OPENAI_MODEL,
                "configured": True,
                "latency_ms": elapsed_ms,
                "error": str(e),
            }

    try:
        async with httpx.AsyncClient(timeout=timeout_s) as client:
            r = await client.get(f"{OLLAMA_URL.rstrip('/')}/api/tags")
        elapsed_ms = int((time.perf_counter() - started) * 1000)

        if r.status_code != 200:
            return {
                "status": "error",
                "provider": "ollama",
                "model": OLLAMA_MODEL,
                "configured": True,
                "url": OLLAMA_URL,
                "latency_ms": elapsed_ms,
                "status_code": r.status_code,
                "error": f"Ollama tags check failed: {r.status_code}",
            }

        model_present = False
        try:
            data = r.json()
            models = data.get("models", []) if isinstance(data, dict) else []
            model_present = any(
                isinstance(m, dict) and m.get("name") == OLLAMA_MODEL
                for m in models
            )
        except Exception:
            model_present = False

        if model_present:
            return {
                "status": "ok",
                "provider": "ollama",
                "model": OLLAMA_MODEL,
                "configured": True,
                "url": OLLAMA_URL,
                "latency_ms": elapsed_ms,
                "status_code": 200,
                "model_present": True,
            }

        return {
            "status": "error",
            "provider": "ollama",
            "model": OLLAMA_MODEL,
            "configured": True,
            "url": OLLAMA_URL,
            "latency_ms": elapsed_ms,
            "status_code": 200,
            "model_present": False,
            "error": f"Model '{OLLAMA_MODEL}' is not available in Ollama",
        }
    except Exception as e:
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return {
            "status": "error",
            "provider": "ollama",
            "model": OLLAMA_MODEL,
            "configured": True,
            "url": OLLAMA_URL,
            "latency_ms": elapsed_ms,
            "error": str(e),
        }


@app.get("/health")
async def health():
    provider = _normalize_provider()
    rag_check, llm_check = await asyncio.gather(
        _check_rag_health(),
        _check_llm_health(provider),
    )

    llm_ok = llm_check.get("status") == "ok"
    rag_ok = rag_check.get("status") in {"ok", "skipped"}
    overall_ok = llm_ok and rag_ok

    payload = {
        "status": "ok" if overall_ok else "degraded",
        "service": "ai-backend",
        "provider": provider,
        "response_format_version": RESPONSE_FORMAT_VERSION,
        "security": {
            "api_key_configured": bool(API_KEY),
        },
        "dependencies": {
            "rag": rag_check,
            "llm": llm_check,
        },
    }

    return JSONResponse(content=payload, status_code=200 if overall_ok else 503)


@app.post("/api/chat")
async def chat(request: ChatRequest, api_key: str = Depends(verify_api_key)):
    """
    Generate a chat message following Ollama API spec
    Requires valid API key in X-API-Key header
    """
    if not request.messages or len(request.messages) == 0:
        raise HTTPException(status_code=400, detail="Messages array cannot be empty")
    
    provider = LLM_PROVIDER
    if provider == "openai":
        model = request.model or OPENAI_MODEL
    else:
        provider = "ollama"
        model = request.model or OLLAMA_MODEL

    def stream_text_response(text: str):
        async def _gen():
            if text:
                yield json.dumps({"token": text, "done": False}) + "\n"
            yield json.dumps({"response": text, "done": True}) + "\n"
        return StreamingResponse(_gen(), media_type="application/x-ndjson")
    
    # ========================================================================
    # TICKER DETECTION + RAG GROUNDING
    # ========================================================================
    
    rag_context = None
    rag_sources = None
    ticker_mode = False
    ticker_symbol = None
    ticker_data = None
    ticker_facts_text = None
    ticker_analysis_heading = None
    
    # Get last user message
    user_last = next((m.content for m in reversed(request.messages) if m.role == "user"), "")
    
    # Detect language for response formatting
    user_lang = _detect_language(user_last)
    
    # STEP 1: Try ticker detection if RAG is available
    explicit_ticker_signal = _has_explicit_ticker_signal(user_last)
    if RAG_URL and user_last and explicit_ticker_signal:
        ticker_symbol, ticker_data, error_code = await detect_ticker_via_rag(
            user_last, 
            RAG_URL, 
            timeout_s=5.0
        )
        
        if ticker_symbol and ticker_data:
            # Valid ticker found - enter ticker mode
            ticker_mode = True
            logger.info(f"Ticker mode activated: {ticker_symbol}")
        
        elif error_code == "timeout":
            # RAG timeout - return helpful error
            msg = (
                "Не могу проверить тикер — сервис перегружен. Попробуй через минуту."
                if user_lang == "ru"
                else "Cannot verify ticker right now — service timeout. Try again in a minute."
            )
            return stream_text_response(msg)
        
        elif error_code == "not_found" and explicit_ticker_signal:
            # Strong ticker context but no verified ticker found
            # This is "soft fail" - only trigger if context is strong
            msg = (
                "Не нашёл подтверждённых данных по этому тикеру. "
                "Пришли точный символ (латиницей) или адрес контракта."
                if user_lang == "ru"
                else "I couldn't find verified data for that ticker. "
                "Please send the exact symbol (Latin letters) or contract address."
            )
            return stream_text_response(msg)
        
        # If error_code == "not_found" but context is NOT strong,
        # fall through to normal LLM answer (user might be asking about something else)
    
    # STEP 2: Build deterministic facts block for ticker mode
    if ticker_mode and ticker_data:
        ticker_facts_text = _build_ticker_facts_block(ticker_data, ticker_symbol, user_lang)
        ticker_analysis_heading = "\n💡 Обзор:" if user_lang == "ru" else "\n💡 Overview:"
        deterministic_overview = _build_deterministic_ticker_overview(ticker_data, user_lang)
        return stream_text_response(f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n{deterministic_overview}")

    # STEP 2: Try general RAG query if not in ticker mode
    if RAG_URL and not ticker_mode and user_last:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                rag_start = time.perf_counter()
                encoded_query = urllib.parse.quote(user_last)
                r = await client.get(f"{RAG_URL.rstrip('/')}/query?q={encoded_query}")
                if r.status_code == 200:
                    try:
                        data = r.json()
                        if isinstance(data, dict):
                            rag_context = data.get("context", [])
                            rag_sources = data.get("sources", [])
                    except:
                        pass
                rag_elapsed_ms = int((time.perf_counter() - rag_start) * 1000)
                logger.info(f"RAG query: {rag_elapsed_ms}ms, status={r.status_code}")
        except:
            pass
    
    # ========================================================================
    # BUILD MESSAGES FOR OLLAMA
    # ========================================================================
    
    messages_dict = []
    
    if ticker_mode and ticker_data:
        # Ticker mode: facts are rendered deterministically; LLM writes analysis only.
        # Build MINIMAL facts for overview generation (no numbers to tempt the model)
        facts_for_overview = {
            "symbol": ticker_data.get("symbol") or ticker_symbol,
            "type": ticker_data.get("type") or "token",
        }
        
        # Only add last_activity if present (to allow "recent activity" context)
        last_activity = ticker_data.get("last_activity")
        if last_activity:
            facts_for_overview["last_activity"] = last_activity

        ticker_prompt = (
            f"Reply ONLY in {'Russian' if user_lang == 'ru' else 'English'}.\n"
            "Write 2-4 sentences of safe qualitative analysis for this token type.\n"
            "\n"
            "STRICT RULES:\n"
            "- DO NOT mention any numbers, metrics, or statistics\n"
            "- DO NOT repeat facts already shown above\n"
            "- DO NOT invent facts not in <REFERENCE_FACTS> (no claims about Telegram, exchanges, listings, control, profitability, mass adoption)\n"
            "- DO NOT use any non-Russian characters if Russian mode (no English, Chinese, Arabic, etc.)\n"
            "- DO NOT use any non-English characters if English mode (no Russian, Chinese, etc.)\n"
            "- Focus ONLY on general characteristics that apply to this TOKEN TYPE\n"
            "- Do NOT make claims about specific adoption, popularity, or success\n"
            "\n"
            "If you cannot write 2-4 safe sentences with the data provided, output exactly:\n"
            f"{'Недостаточно данных для анализа.' if user_lang == 'ru' else 'Insufficient data for analysis.'}\n"
            "\n"
            "Good example (EN): 'This jetton operates within the TON blockchain ecosystem. The token structure indicates standard fungible asset characteristics.'\n"
            "Bad example (EN): 'This token has massive adoption with millions of holders.' (invents claims not in data)\n"
        )
        
        reference_facts = (
            "<REFERENCE_FACTS>\n"
            + json.dumps(facts_for_overview, ensure_ascii=False, indent=2)
            + "\n</REFERENCE_FACTS>"
        )
        
        messages_dict.append({"role": "system", "content": ticker_prompt})
        messages_dict.append({"role": "system", "content": reference_facts})
    
    elif rag_context:
        # General RAG mode: inject context for broader queries
        context_block = "\n\n---\n\n".join(rag_context)
        sys_msg = (
            "You are an AI assistant for TON/token analysis.\n"
            "Use ONLY the context below. If the context is insufficient, say you don't have enough data.\n"
            "Avoid hard price predictions; provide scenarios and risks instead.\n\n"
            f"CONTEXT:\n{context_block}"
        )
        messages_dict.append({"role": "system", "content": sys_msg})
    
    # Add user messages
    for msg in request.messages:
        msg_dict = {
            "role": msg.role,
            "content": msg.content
        }
        # Add optional fields if present
        if msg.images:
            msg_dict["images"] = msg.images
        if msg.tool_calls:
            msg_dict["tool_calls"] = msg.tool_calls
        messages_dict.append(msg_dict)
    
    # ========================================================================
    # BUILD PROVIDER REQUEST
    # ========================================================================

    if request.options:
        # Convert ModelOptions to dict, excluding None values
        options_dict = request.options.model_dump(exclude_none=True)
    else:
        # Default options for backward compatibility with existing clients
        options_dict = {
            "num_ctx": 2048,
            "num_predict": 256,
            "temperature": 0.3,
            "top_p": 0.9,
            "repeat_penalty": 1.1,
            "num_thread": 2,
        }

    ollama_request = {
        "model": model,
        "messages": messages_dict,
        "stream": request.stream,
    }
    if request.tools:
        ollama_request["tools"] = request.tools
    if request.format:
        ollama_request["format"] = request.format
    if options_dict:
        ollama_request["options"] = options_dict
    if request.think is not None:
        ollama_request["think"] = request.think
    if request.keep_alive is not None:
        ollama_request["keep_alive"] = request.keep_alive
    if request.logprobs is not None:
        ollama_request["logprobs"] = request.logprobs
    if request.top_logprobs is not None:
        ollama_request["top_logprobs"] = request.top_logprobs

    # OpenAI request uses the same chat history, but only role/content fields.
    openai_messages = [
        {
            "role": msg["role"],
            "content": msg.get("content", ""),
        }
        for msg in messages_dict
    ]
    openai_request = {
        "model": model,
        "messages": openai_messages,
        "stream": request.stream,
    }
    # Map compatible sampling options when present.
    if options_dict.get("temperature") is not None:
        openai_request["temperature"] = options_dict["temperature"]
    if options_dict.get("top_p") is not None:
        openai_request["top_p"] = options_dict["top_p"]
    if options_dict.get("num_predict") is not None:
        openai_request["max_tokens"] = options_dict["num_predict"]

    # ========================================================================
    # STREAM RESPONSE FROM LLM PROVIDER
    # ========================================================================

    def _combine_ticker_output(narrative: str) -> str:
        if not ticker_facts_text:
            return narrative
        narrative_clean = _sanitize_ticker_narrative(narrative, user_lang)
        return f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n{narrative_clean}"

    async def generate_ollama_response():
        inference_start = time.perf_counter()
        first_token_logged = False
        prefix_sent = False

        async with httpx.AsyncClient(timeout=60.0) as client:
            if ticker_facts_text:
                prefix = f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n"
                yield json.dumps({"token": prefix, "done": False}) + "\n"
                prefix_sent = True
            async with client.stream(
                "POST",
                f"{OLLAMA_URL}/api/chat",
                json=ollama_request
            ) as response:
                stream_open_ms = int((time.perf_counter() - inference_start) * 1000)
                logger.info(f"Ollama stream opened: {stream_open_ms}ms, model={model}")

                if response.status_code != 200:
                    error_detail = "Unknown error"
                    try:
                        error_text = await response.aread()
                        error_data = json.loads(error_text)
                        error_detail = error_data.get("error", str(error_text))
                    except Exception:
                        error_detail = str(response.status_code)

                    if ticker_facts_text:
                        fallback = _combine_ticker_output(
                            "Анализ недоступен в данный момент."
                            if user_lang == "ru"
                            else "Analysis is unavailable right now."
                        )
                        if not prefix_sent:
                            yield json.dumps({"token": f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n", "done": False}) + "\n"
                        yield json.dumps({"response": fallback, "done": True}) + "\n"
                    else:
                        yield json.dumps({"error": f"Ollama error: {error_detail}"}) + "\n"
                    return

                full_response = ""
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        data = json.loads(line)

                        # Ollama /api/chat streaming format
                        if "message" in data and isinstance(data["message"], dict):
                            content = data["message"].get("content", "")
                            if content:
                                if not first_token_logged:
                                    ttft_ms = int((time.perf_counter() - inference_start) * 1000)
                                    logger.info(f"First token: {ttft_ms}ms, model={model}")
                                    first_token_logged = True

                                full_response += content
                                # In ticker mode, buffer narrative and emit only vetted final output.
                                if not ticker_facts_text:
                                    # Keep token chunks non-terminal so clients wait for final `response` payload.
                                    yield json.dumps({"token": content, "done": False}) + "\n"

                        if data.get("done", False):
                            total_ms = int((time.perf_counter() - inference_start) * 1000)
                            logger.info(f"Total time: {total_ms}ms, model={model}")
                            yield json.dumps({"response": _combine_ticker_output(full_response), "done": True}) + "\n"
                            break

                    except json.JSONDecodeError:
                        logger.warning(f"Failed to parse JSON line: {line[:100]}")
                        continue

    async def generate_openai_response():
        if not OPENAI_API_KEY:
            yield json.dumps({"error": "OPENAI_API_KEY is required when LLM_PROVIDER=openai"}) + "\n"
            return

        inference_start = time.perf_counter()
        first_token_logged = False
        full_response = ""
        prefix_sent = False
        headers = {
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=60.0) as client:
            if ticker_facts_text:
                prefix = f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n"
                yield json.dumps({"token": prefix, "done": False}) + "\n"
                prefix_sent = True
            if request.stream:
                async with client.stream(
                    "POST",
                    "https://api.openai.com/v1/chat/completions",
                    headers=headers,
                    json=openai_request,
                ) as response:
                    stream_open_ms = int((time.perf_counter() - inference_start) * 1000)
                    logger.info(f"OpenAI stream opened: {stream_open_ms}ms, model={model}")

                    if response.status_code != 200:
                        error_detail = str(response.status_code)
                        try:
                            payload = await response.aread()
                            error_data = json.loads(payload)
                            if isinstance(error_data, dict):
                                error_obj = error_data.get("error", {})
                                error_detail = error_obj.get("message", error_detail)
                        except Exception:
                            pass
                        if ticker_facts_text:
                            fallback = _combine_ticker_output(
                                "Анализ недоступен в данный момент."
                                if user_lang == "ru"
                                else "Analysis is unavailable right now."
                            )
                            if not prefix_sent:
                                yield json.dumps({"token": f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n", "done": False}) + "\n"
                            yield json.dumps({"response": fallback, "done": True}) + "\n"
                        else:
                            yield json.dumps({"error": f"OpenAI error: {error_detail}"}) + "\n"
                        return

                    async for line in response.aiter_lines():
                        if not line or not line.startswith("data: "):
                            continue
                        data_str = line[6:].strip()
                        if data_str == "[DONE]":
                            break
                        try:
                            data = json.loads(data_str)
                        except json.JSONDecodeError:
                            continue

                        choices = data.get("choices") or []
                        if not choices:
                            continue
                        delta = choices[0].get("delta") or {}
                        content = delta.get("content")
                        if content:
                            if not first_token_logged:
                                ttft_ms = int((time.perf_counter() - inference_start) * 1000)
                                logger.info(f"First token: {ttft_ms}ms, model={model}")
                                first_token_logged = True
                            full_response += content
                            # In ticker mode, buffer narrative and emit only vetted final output.
                            if not ticker_facts_text:
                                yield json.dumps({"token": content, "done": False}) + "\n"

                    total_ms = int((time.perf_counter() - inference_start) * 1000)
                    logger.info(f"Total time: {total_ms}ms, model={model}")
                    yield json.dumps({"response": _combine_ticker_output(full_response), "done": True}) + "\n"
                    return

            response = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers=headers,
                json=openai_request,
            )
            if response.status_code != 200:
                error_detail = str(response.status_code)
                try:
                    error_data = response.json()
                    if isinstance(error_data, dict):
                        error_obj = error_data.get("error", {})
                        error_detail = error_obj.get("message", error_detail)
                except Exception:
                    pass
                if ticker_facts_text:
                    fallback = _combine_ticker_output(
                        "Анализ недоступен в данный момент."
                        if user_lang == "ru"
                        else "Analysis is unavailable right now."
                    )
                    if not prefix_sent:
                        yield json.dumps({"token": f"{ticker_facts_text}\n\n{ticker_analysis_heading}\n", "done": False}) + "\n"
                    yield json.dumps({"response": fallback, "done": True}) + "\n"
                else:
                    yield json.dumps({"error": f"OpenAI error: {error_detail}"}) + "\n"
                return

            data = response.json()
            choices = data.get("choices") or []
            if choices:
                message = choices[0].get("message") or {}
                full_response = message.get("content", "") or ""
            if full_response:
                yield json.dumps({"token": full_response, "done": False}) + "\n"
            yield json.dumps({"response": _combine_ticker_output(full_response), "done": True}) + "\n"

    async def generate_response():
        try:
            if provider == "openai":
                async for chunk in generate_openai_response():
                    yield chunk
                return
            async for chunk in generate_ollama_response():
                yield chunk
        except httpx.TimeoutException:
            yield json.dumps({"error": "Request timeout - AI model took too long to respond"}) + "\n"
        except httpx.RequestError as e:
            if provider == "openai":
                yield json.dumps({"error": f"Cannot connect to OpenAI API. Error: {str(e)}"}) + "\n"
            else:
                yield json.dumps({"error": f"Cannot connect to Ollama at {OLLAMA_URL}. Error: {str(e)}"}) + "\n"
        except Exception as e:
            logger.exception("Unexpected error in generate_response")
            yield json.dumps({"error": f"Internal server error: {str(e)}"}) + "\n"

    return StreamingResponse(generate_response(), media_type="application/x-ndjson")


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
