from __future__ import annotations

import hashlib
import re
from typing import Dict

import httpx

# Simple in-memory cache: key -> localized prompt text.
_PROMPT_CACHE: Dict[str, str] = {}

# Terms/placeholders we should never translate.
_PROTECTED_PATTERNS = (
    r"\bTON\b",
    r"\bjetton\b",
    r"\bREFERENCE_FACTS\b",
    r"\bNARRATIVE\b",
    r"\bDOGS\b",
    r"\bCATS\b",
    r"https?://[^\s)]+",
    r"\{[A-Z0-9_]+\}",
)


def _cache_key(template_en: str, target_lang: str, provider: str, model: str) -> str:
    src = f"{provider}|{model}|{target_lang}|{template_en}"
    return hashlib.sha256(src.encode("utf-8")).hexdigest()


def _protect_terms(text: str) -> tuple[str, Dict[str, str]]:
    protected: Dict[str, str] = {}
    masked = text
    idx = 0

    for pattern in _PROTECTED_PATTERNS:
        for m in list(re.finditer(pattern, masked, flags=re.IGNORECASE)):
            original = m.group(0)
            token = f"__KEEP_{idx}__"
            idx += 1
            protected[token] = original
            masked = masked[:m.start()] + token + masked[m.end():]
            # Restart for this pattern because indices changed.
            break

    # Re-run until no more replacements for all patterns.
    changed = True
    while changed:
        changed = False
        for pattern in _PROTECTED_PATTERNS:
            m = re.search(pattern, masked, flags=re.IGNORECASE)
            if not m:
                continue
            original = m.group(0)
            token = f"__KEEP_{idx}__"
            idx += 1
            protected[token] = original
            masked = masked[:m.start()] + token + masked[m.end():]
            changed = True
    return masked, protected


def _restore_terms(text: str, protected: Dict[str, str]) -> str:
    restored = text
    for token, original in protected.items():
        restored = restored.replace(token, original)
    return restored


async def localize_prompt_with_model(
    *,
    template_en: str,
    target_lang: str,
    provider: str,
    ollama_url: str,
    ollama_model: str,
    openai_api_key: str | None,
    openai_model: str,
    timeout_s: float = 25.0,
) -> str:
    """Translate English instruction prompt into target language with cache.

    Falls back to the original English template on any failure.
    """
    lang = (target_lang or "").strip().lower()
    if not template_en or not lang or lang in ("en", "english"):
        return template_en

    chosen_provider = (provider or "ollama").strip().lower()
    model_name = openai_model if chosen_provider == "openai" else ollama_model
    key = _cache_key(template_en, lang, chosen_provider, model_name)
    cached = _PROMPT_CACHE.get(key)
    if cached:
        return cached

    masked_template, protected = _protect_terms(template_en)
    translator_instruction = (
        "Translate the following instruction text into the target language.\n"
        "Rules:\n"
        "- Preserve structure, bullets, and line breaks.\n"
        "- Keep placeholder tokens like __KEEP_0__ exactly unchanged.\n"
        "- Return ONLY translated instruction text, no explanations.\n"
    )
    translation_request = (
        f"Target language: {lang}\n\n"
        "TEXT TO TRANSLATE:\n"
        f"{masked_template}"
    )

    try:
        async with httpx.AsyncClient(timeout=timeout_s) as client:
            if chosen_provider == "openai":
                if not openai_api_key:
                    return template_en
                payload = {
                    "model": openai_model,
                    "messages": [
                        {"role": "system", "content": translator_instruction},
                        {"role": "user", "content": translation_request},
                    ],
                    "stream": False,
                    "temperature": 0,
                }
                resp = await client.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {openai_api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                if resp.status_code != 200:
                    return template_en
                data = resp.json()
                choices = data.get("choices") or []
                if not choices:
                    return template_en
                translated = ((choices[0].get("message") or {}).get("content") or "").strip()
            else:
                payload = {
                    "model": ollama_model,
                    "messages": [
                        {"role": "system", "content": translator_instruction},
                        {"role": "user", "content": translation_request},
                    ],
                    "stream": False,
                    "options": {"temperature": 0},
                }
                resp = await client.post(f"{ollama_url.rstrip('/')}/api/chat", json=payload)
                if resp.status_code != 200:
                    return template_en
                data = resp.json()
                translated = ((data.get("message") or {}).get("content") or "").strip()
    except Exception:
        return template_en

    if not translated:
        return template_en

    restored = _restore_terms(translated, protected)
    _PROMPT_CACHE[key] = restored
    return restored

