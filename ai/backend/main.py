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
import hashlib
from pathlib import Path
from dotenv import load_dotenv
from prompt_i18n import localize_prompt_with_model

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
INNER_CALLS_KEY = (os.getenv("INNER_CALLS_KEY") or os.getenv("API_KEY") or "").strip()


def _mask_secret(value: str, visible: int = 4) -> str:
    if not value:
        return "(missing)"
    if len(value) <= visible * 2:
        return "*" * len(value)
    return f"{value[:visible]}...{value[-visible:]}"


def _key_fingerprint(value: str) -> str:
    if not value:
        return "(missing)"
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:6]


def _log_runtime_env_snapshot() -> None:
    provider = "openai" if LLM_PROVIDER == "openai" else "ollama"
    logger.info("[ENV][AI] runtime configuration snapshot")
    logger.info("[ENV][AI] provider=%s", provider)
    logger.info("[ENV][AI] INNER_CALLS_KEY configured=%s preview=%s", bool(INNER_CALLS_KEY), _mask_secret(INNER_CALLS_KEY))
    logger.info("[ENV][AI] INNER_CALLS_KEY sha256_prefix=%s", _key_fingerprint(INNER_CALLS_KEY))
    logger.info("[ENV][AI] RAG_URL=%s", RAG_URL or "(missing)")
    logger.info("[ENV][AI] OLLAMA_URL=%s", OLLAMA_URL or "(missing)")
    logger.info("[ENV][AI] OLLAMA_MODEL=%s", OLLAMA_MODEL or "(missing)")
    logger.info("[ENV][AI] OPENAI_MODEL=%s", OPENAI_MODEL or "(missing)")
    logger.info("[ENV][AI] OPENAI_API_KEY configured=%s", bool(OPENAI_API_KEY))


def _inner_calls_headers() -> Dict[str, str]:
    if not INNER_CALLS_KEY:
        return {}
    return {"X-API-Key": INNER_CALLS_KEY}


def _env_bool(name: str, default: bool) -> bool:
    raw = (os.getenv(name) or "").strip().lower()
    if raw in {"1", "true", "yes", "on"}:
        return True
    if raw in {"0", "false", "no", "off"}:
        return False
    return default

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
        
        # +3: Has meaningful uppercase signal (not just sentence TitleCase like "Tell")
        elif any(c.isupper() for c in token):
            is_titlecase_word = (
                len(token) > 1
                and token[0].isupper()
                and token[1:].islower()
            )
            if not is_titlecase_word:
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
                    r = await client.get(
                        f"{rag_url.rstrip('/')}/tokens/{symbol}",
                        headers=_inner_calls_headers(),
                    )
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


def _detect_requested_output_language(messages: List["ChatMessage"], fallback_lang: str) -> str:
    """Detect explicit language request from upstream system prompts."""
    for msg in messages:
        try:
            if msg.role != "system":
                continue
            content = (msg.content or "").lower()
            if not content:
                continue
            if ("strictly in russian" in content) or ("только на русском" in content) or ("строго на русском" in content):
                return "ru"
            if ("strictly in english" in content) or ("only in english" in content):
                return "en"
        except Exception:
            continue
    return fallback_lang


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


def _truncate_text(value: str, max_len: int = 180) -> str:
    text = (value or "").strip()
    if len(text) <= max_len:
        return text
    return text[: max_len - 1].rstrip() + "..."


def _format_verified(value: Any, user_lang: str) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, bool):
        return ("да" if value else "нет") if user_lang == "ru" else ("yes" if value else "no")
    text = str(value).strip()
    if not text:
        return None
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
    symbol = str(ticker_data.get("symbol") or ticker_symbol or "UNKNOWN").upper()
    token_type = str(ticker_data.get("type") or "token").lower()

    # RAW VALUES - exactly as fetched
    supply_raw = ticker_data.get("total_supply")
    holders_raw = ticker_data.get("holders")
    description_raw = ticker_data.get("description")
    contract_raw = ticker_data.get("id") or ticker_data.get("address") or ticker_data.get("contract")
    decimals_raw = ticker_data.get("decimals")
    verified_raw = ticker_data.get("verified")
    
    # Format raw integers with commas for readability (but keep them accurate)
    supply_display = _metric_display(supply_raw) if supply_raw is not None else None
    holders_display = _metric_display(holders_raw) if holders_raw is not None else None
    description_display = _truncate_text(str(description_raw).strip()) if description_raw is not None else ""
    contract_display = str(contract_raw).strip() if contract_raw is not None else ""
    decimals_display = _metric_display(decimals_raw) if decimals_raw is not None else None
    verified_display = _format_verified(verified_raw, user_lang)

    if user_lang == "ru":
        lines = [
            f"${symbol} токен",
            "",
            "Blockchain: TON",
            f"Выпуск: {supply_display if supply_display else 'неизвестно'}",
            f"Держатели: {holders_display if holders_display else 'неизвестно'}",
        ]
        if token_type == "jetton" and contract_display:
            lines.append(f"Контракт: {contract_display}")
        if decimals_display:
            lines.append(f"Decimals: {decimals_display}")
        if verified_display:
            lines.append(f"Verified: {verified_display}")
        if description_display:
            lines.append(f"Описание: {description_display}")
        
    else:
        lines = [
            f"${symbol} token",
            "",
            "Blockchain: TON",
            f"Supply: {supply_display if supply_display else 'not available'}",
            f"Holders: {holders_display if holders_display else 'not available'}",
        ]
        if token_type == "jetton" and contract_display:
            lines.append(f"Contract: {contract_display}")
        if decimals_display:
            lines.append(f"Decimals: {decimals_display}")
        if verified_display:
            lines.append(f"Verified: {verified_display}")
        if description_display:
            lines.append(f"Description: {description_display}")
    
    return "\n".join(lines)


_CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")


def _narrative_fallback(user_lang: str) -> str:
    return "Недостаточно данных для анализа." if user_lang == "ru" else "Insufficient data for analysis."


def _contains_plain_fallback_phrase(text: str, user_lang: str) -> bool:
    raw = (text or "").strip().lower()
    if not raw:
        return True
    if user_lang == "ru":
        return "недостаточно данных для анализа" in raw
    return "insufficient data for analysis" in raw


def _sanitize_ticker_narrative(narrative: str, user_lang: str) -> str:
    text = re.sub(r"\s+", " ", (narrative or "").strip())
    if not text:
        return _narrative_fallback(user_lang)
    # Keep narrative permissive so model can use available facts imaginatively.
    # Only block obvious malformed/mixed-script garbage.
    if _CJK_RE.search(text):
        return _narrative_fallback(user_lang)
    return text


def _normalize_paragraph_spacing(text: str) -> str:
    """Keep exactly one empty line between sections/paragraphs."""
    cleaned = (text or "").replace("\r\n", "\n")
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _ensure_ticker_identity_in_narrative(narrative: str, token_name: str, token_symbol: str, user_lang: str) -> str:
    """Guarantee narrative explicitly references token identity (name/symbol)."""
    text = (narrative or "").strip()
    if not text:
        return text

    lower = text.lower()
    name_present = bool(token_name and token_name.strip() and token_name.strip().lower() in lower)
    symbol_present = bool(token_symbol and token_symbol.strip() and token_symbol.strip().lower() in lower)
    if name_present or symbol_present:
        return text

    if user_lang == "ru":
        prefix = f"Для {token_name or token_symbol} ({token_symbol}) этот нарратив связан с мемной идентичностью сообщества в TON."
    else:
        prefix = f"For {token_name or token_symbol} ({token_symbol}), this narrative centers on meme identity and community culture in TON."
    return f"{prefix} {text}"


def _strip_stat_repetition(narrative: str, user_lang: str) -> str:
    """Remove narrative sentences that just repeat stats already shown above."""
    text = (narrative or "").strip()
    if not text:
        return text

    parts = re.split(r"(?<=[.!?])\s+", text)
    stat_en = ("supply", "holders", "holder", "last activity", "market cap", "circulating")
    stat_ru = ("выпуск", "держател", "холдер", "последн", "активност", "капитализац")
    stat_terms = stat_ru if user_lang == "ru" else stat_en

    filtered = []
    for part in parts:
        lower = part.lower()
        if any(term in lower for term in stat_terms):
            continue
        filtered.append(part.strip())

    # If we stripped too aggressively, keep original so we don't return empty output.
    cleaned = " ".join(p for p in filtered if p).strip()
    return cleaned or text


def _descriptive_narrative_fallback(name: str, symbol: str, user_lang: str) -> str:
    token_label = name or symbol or "This token"
    token_upper = f"{name} {symbol}".upper()
    animal_hint = None
    if "DOG" in token_upper:
        animal_hint = "dog"
    elif "CAT" in token_upper:
        animal_hint = "cat"
    if user_lang == "ru":
        if animal_hint == "dog":
            return (
                f"{token_label} строит нарратив вокруг образа собак как интернет-мема: это символ дружелюбного, массового и узнаваемого комьюнити в TON.\n\n"
                "Вероятнее всего, токен появился как культурный маркер сообщества, где ценится вовлечённость, юмор и общий вайб, а не только формальные метрики."
            )
        if animal_hint == "cat":
            return (
                f"{token_label} опирается на узнаваемый образ котов в интернет-культуре и подаётся как мемный символ сообщества TON.\n\n"
                "Скорее всего, такой токен появился для усиления комьюнити-идентичности: через иронию, визуальный стиль и участие в общем культурном сюжете."
            )
        return (
            f"{token_label} подаётся как мемный актив в экосистеме TON: образ строится вокруг узнаваемого интернет-персонажа и культуры шеринга.\n\n"
            "Обычно такие токены появляются как социальный маркер сообщества: людям важны не столько метрики, сколько идентичность, юмор и участие в общем нарративе."
        )
    if animal_hint == "dog":
        return (
            f"{token_label} leans into dog-meme internet culture as a recognizable identity symbol inside TON.\n\n"
            "It most likely appeared as a community marker where participation, humor, and shared vibe matter more than raw metrics."
        )
    if animal_hint == "cat":
        return (
            f"{token_label} leans into cat-meme internet culture as a recognizable identity symbol inside TON.\n\n"
            "It likely emerged as a community-first token built around style, irony, and shared participation rather than purely technical positioning."
        )
    return (
        f"{token_label} is framed as a meme asset within the TON ecosystem, built around recognizable internet character culture and shareable identity.\n\n"
        "Tokens like this usually emerge as community symbols: people engage less for hard metrics and more for vibe, belonging, and participation in a common narrative."
    )


def _is_generic_ton_boilerplate(text: str, user_lang: str) -> bool:
    t = (text or "").lower()
    if not t:
        return False
    if user_lang == "ru":
        markers = (
            "экосистем", "блокчейн", "децентрализ", "цифров", "nft", "defi", "технолог",
        )
    else:
        markers = (
            "ton ecosystem", "blockchain technology", "digital asset", "decentralized finance", "defi", "nft",
        )
    hit_count = sum(1 for m in markers if m in t)
    return hit_count >= 2


def _is_utility_boilerplate(text: str, user_lang: str) -> bool:
    t = (text or "").lower()
    if not t:
        return False
    if user_lang == "ru":
        markers = (
            "использует", "используется", "для транзакц", "dapp", "децентрализ", "цифровой актив",
        )
    else:
        markers = (
            "used for transactions", "used in transactions", "decentralized applications",
            "digital asset", "utility token", "dapp", "defi projects",
        )
    return sum(1 for m in markers if m in t) >= 1


def _has_excessive_latin_in_ru(text: str) -> bool:
    """Detect RU narratives polluted by long English fragments."""
    if not text:
        return False
    cyr = len(re.findall(r"[А-Яа-яЁё]", text))
    lat = len(re.findall(r"[A-Za-z]", text))
    if lat == 0:
        return False
    # Allow token symbols/TON names, but reject mixed-language paragraphs.
    if cyr == 0:
        return True
    return (lat / max(cyr, 1)) > 0.35


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

API_KEY = INNER_CALLS_KEY


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


@app.on_event("startup")
async def _on_startup_log_env() -> None:
    _log_runtime_env_snapshot()

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


def _default_model_for_provider(provider: str) -> str:
    if provider == "openai":
        return OPENAI_MODEL
    return OLLAMA_MODEL


def _build_capabilities_payload() -> Dict[str, Any]:
    """
    Stable capabilities contract for smoke checks and provider swap traceability.
    Capability flags are env-overridable to avoid false claims during rollout.
    """
    provider = _normalize_provider()
    model = _default_model_for_provider(provider)

    streaming = _env_bool("CAP_STREAMING", True)
    # Conservative default for tools on ollama; most OpenAI-compatible providers support it.
    default_tools = provider == "openai"
    tools = _env_bool("CAP_TOOLS", default_tools)
    images = _env_bool("CAP_IMAGES", False)
    video = _env_bool("CAP_VIDEO", False)

    caps = {
        "streaming": streaming,
        "tools": tools,
        "images": images,
        "video": video,
    }

    return {
        "status": "ok",
        "service": "ai-backend",
        "provider": provider,
        "model": model,
        "response_format_version": RESPONSE_FORMAT_VERSION,
        # Keep top-level flags for simple consumers.
        **caps,
        # Also expose a nested block for forward-compatible capability expansion.
        "capabilities": caps,
    }


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
            r = await client.get(
                f"{RAG_URL.rstrip('/')}/health",
                headers=_inner_calls_headers(),
            )
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


@app.get("/capabilities")
async def capabilities():
    return JSONResponse(content=_build_capabilities_payload(), status_code=200)


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
    ton_only_narrative = False
    ticker_name_for_narrative = ""
    
    # Get last user message
    user_last = next((m.content for m in reversed(request.messages) if m.role == "user"), "")
    
    # Detect language for response formatting.
    # Respect explicit upstream system language instructions (EN/RU buttons).
    user_lang = _detect_language(user_last)
    user_lang = _detect_requested_output_language(request.messages, user_lang)
    
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
    
    # STEP 2: Build deterministic facts block for ticker mode.
    # Narrative is generated later by the LLM under strict guardrails.
    if ticker_mode and ticker_data:
        ticker_facts_text = _build_ticker_facts_block(ticker_data, ticker_symbol, user_lang)

    # STEP 2: Try general RAG query if not in ticker mode
    if RAG_URL and not ticker_mode and user_last:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                rag_start = time.perf_counter()
                encoded_query = urllib.parse.quote(user_last)
                r = await client.get(
                    f"{RAG_URL.rstrip('/')}/query?q={encoded_query}",
                    headers=_inner_calls_headers(),
                )
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
        # Ticker mode: facts are rendered deterministically; LLM writes narrative.
        facts_for_narrative = {
            "symbol": ticker_data.get("symbol") or ticker_symbol,
            "name": ticker_data.get("name"),
            "type": ticker_data.get("type") or "token",
            "description": ticker_data.get("description"),
            "total_supply": ticker_data.get("total_supply"),
            "holders": ticker_data.get("holders"),
        }

        last_activity = ticker_data.get("last_activity")
        if last_activity:
            facts_for_narrative["last_activity"] = last_activity

        source_name = _resolve_token_source(ticker_data)
        ton_only_from_source = "tokens.swap.coffee" in source_name.lower()
        ton_only_narrative = ton_only_from_source
        ticker_name_for_narrative = str(ticker_data.get("name") or ticker_symbol or "")
        ton_scope_rule_en = (
            "- Treat this asset strictly as part of the TON ecosystem.\n"
            "- DO NOT claim or imply that it belongs to any non-TON blockchain."
            if ton_only_from_source
            else "- Keep blockchain context consistent with REFERENCE_FACTS."
        )
        language_name = {
            "en": "English",
            "ru": "Russian",
        }.get(user_lang, user_lang)
        ticker_prompt_en = (
            f"Reply ONLY in {language_name}.\n"
            "Write a concise 2-4 sentence narrative.\n"
            "\n"
            "NARRATIVE RULES:\n"
            "- These rules apply only to the Narrative section; do not rewrite or alter the facts/stats block.\n"
            "- Use REFERENCE_FACTS as the primary anchor.\n"
            "- You may use general model knowledge for qualitative context, but do not fabricate specific factual claims.\n"
            "- Start from token identity: interpret the token name/symbol and description cues.\n"
            "- Mention token name or symbol naturally in the narrative.\n"
            "- If description exists in REFERENCE_FACTS, incorporate it explicitly in the first 1-2 sentences.\n"
            "- Do NOT restate supply/holders/last activity or other numeric stats already shown in the stats block.\n"
            "- Focus on the descriptive story: what the meme identity is, why this token likely appeared, and what community narrative it represents.\n"
            "- Prefer cultural/semiotic interpretation: what the symbol means figuratively, why this meme resonates socially, and what philosophy of community participation it signals.\n"
            "- It is acceptable to use soft hypothesis language (for example: likely, may, often) for narrative framing.\n"
            "- Do NOT claim transaction/payment utility unless REFERENCE_FACTS description explicitly says so.\n"
            "- Avoid investment advice, guaranteed outcomes, or hard predictions.\n"
            f"{ton_scope_rule_en}\n"
            "\n"
            "Always provide a narrative using available reference facts.\n"
            "Keep it concise and grounded; avoid fabricated specifics.\n"
        )
        ticker_prompt = await localize_prompt_with_model(
            template_en=ticker_prompt_en,
            target_lang=user_lang,
            provider=LLM_PROVIDER,
            ollama_url=OLLAMA_URL,
            ollama_model=OLLAMA_MODEL,
            openai_api_key=OPENAI_API_KEY,
            openai_model=OPENAI_MODEL,
        )

        reference_facts = (
            "<REFERENCE_FACTS>\n"
            + json.dumps(facts_for_narrative, ensure_ascii=False, indent=2)
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
    
    # Add user messages.
    # In ticker mode, isolate generation from upstream bot system/history prompts:
    # use only current user query + ticker system context.
    if ticker_mode:
        if user_last:
            messages_dict.append({"role": "user", "content": user_last})
    else:
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
        narrative_clean = _strip_stat_repetition(narrative_clean, user_lang)
        if _contains_plain_fallback_phrase(narrative_clean, user_lang):
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        narrative_clean = _ensure_ticker_identity_in_narrative(
            narrative_clean,
            ticker_name_for_narrative,
            str(ticker_symbol or ""),
            user_lang,
        )
        if _is_generic_ton_boilerplate(narrative_clean, user_lang):
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        if _is_utility_boilerplate(narrative_clean, user_lang):
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        if user_lang == "ru" and _has_excessive_latin_in_ru(narrative_clean):
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        if ton_only_narrative:
            non_ton_chain = re.search(
                r"\b(bitcoin|ethereum|dogecoin|solana|tron|bsc|binance\s+smart\s+chain|polygon|avalanche|доджкоин|доге|доги|эфириум|биткоин|солана|трон)\b",
                narrative_clean,
                flags=re.IGNORECASE,
            )
            if non_ton_chain:
                narrative_clean = _descriptive_narrative_fallback(
                    ticker_name_for_narrative,
                    str(ticker_symbol or ""),
                    user_lang,
                )
        if not narrative_clean.strip():
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        # Final safety net: never ship plain fallback phrase in ticker narrative.
        if _contains_plain_fallback_phrase(narrative_clean, user_lang):
            narrative_clean = _descriptive_narrative_fallback(
                ticker_name_for_narrative,
                str(ticker_symbol or ""),
                user_lang,
            )
        response_text = f"{ticker_facts_text}\n\n{narrative_clean}"
        return _normalize_paragraph_spacing(response_text)

    async def generate_ollama_response():
        inference_start = time.perf_counter()
        first_token_logged = False
        prefix_sent = False

        async with httpx.AsyncClient(timeout=60.0) as client:
            if ticker_facts_text:
                prefix = _normalize_paragraph_spacing(f"{ticker_facts_text}\n\n")
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
                        logger.error(
                            "Ticker fallback due to Ollama non-200. status=%s detail=%s provider=%s model=%s rag_url=%s inner_key=%s",
                            response.status_code,
                            error_detail,
                            provider,
                            model,
                            RAG_URL,
                            _mask_secret(INNER_CALLS_KEY),
                        )
                        fallback = _combine_ticker_output(
                            "Анализ недоступен в данный момент."
                            if user_lang == "ru"
                            else "Analysis is unavailable right now."
                        )
                        if not prefix_sent:
                            yield json.dumps({"token": _normalize_paragraph_spacing(f"{ticker_facts_text}\n\n"), "done": False}) + "\n"
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
                prefix = _normalize_paragraph_spacing(f"{ticker_facts_text}\n\n")
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
                            logger.error(
                                "Ticker fallback due to OpenAI stream non-200. status=%s detail=%s provider=%s model=%s rag_url=%s inner_key=%s",
                                response.status_code,
                                error_detail,
                                provider,
                                model,
                                RAG_URL,
                                _mask_secret(INNER_CALLS_KEY),
                            )
                            fallback = _combine_ticker_output(
                                "Анализ недоступен в данный момент."
                                if user_lang == "ru"
                                else "Analysis is unavailable right now."
                            )
                            if not prefix_sent:
                                yield json.dumps({"token": _normalize_paragraph_spacing(f"{ticker_facts_text}\n\n"), "done": False}) + "\n"
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
                    logger.error(
                        "Ticker fallback due to OpenAI non-stream non-200. status=%s detail=%s provider=%s model=%s rag_url=%s inner_key=%s",
                        response.status_code,
                        error_detail,
                        provider,
                        model,
                        RAG_URL,
                        _mask_secret(INNER_CALLS_KEY),
                    )
                    fallback = _combine_ticker_output(
                        "Анализ недоступен в данный момент."
                        if user_lang == "ru"
                        else "Analysis is unavailable right now."
                    )
                    if not prefix_sent:
                        yield json.dumps({"token": _normalize_paragraph_spacing(f"{ticker_facts_text}\n\n"), "done": False}) + "\n"
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
