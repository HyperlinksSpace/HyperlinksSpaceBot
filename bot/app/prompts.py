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
    ),
}

THINKING_TEXT = {
    "en": "Thinking...",
    "ru": "Думаю...",
}


def build_regen_system_prompt(lang: str) -> str:
    if lang == "ru":
        return (
            f"{BASE_SYSTEM_PROMPT}\n"
            "ВАЖНО: отвечай строго на русском языке.\n"
            "Английские слова запрещены, КРОМЕ тикеров, доменов и названий (MCOM, swap.coffee).\n"
            "Не выводи JSON, код, таблицы, списки полей или строки с ';'.\n"
            "Если даны факты о токене — пиши связный описательный нарратив живым языком (обычно 2–5 предложений).\n"
            "Не ограничивайся сухим пересказом метрик; дай контекст и смысл для сообщества.\n"
            "НЕ ПРИДУМЫВАЙ: блокчейн, даты, листинги, продажи токена, команду, цели проекта.\n"
            "Если чего-то нет в фактах — скажи, что данных нет.\n"
        )
    return (
        f"{BASE_SYSTEM_PROMPT}\n"
        "IMPORTANT: respond strictly in English.\n"
        "No Russian.\n"
        "No JSON, no raw data dumps.\n"
        "When token facts are provided, write a coherent descriptive narrative (typically 2-5 sentences).\n"
        "Do not just restate raw metrics; add qualitative community/context framing.\n"
        "Do not invent blockchain, dates, listings, token sales, team, or roadmap.\n"
        "If missing, say data is not available.\n"
    )


def build_default_system_prompt(lang: str) -> str:
    if lang == "ru":
        return (
            f"{BASE_SYSTEM_PROMPT}\n"
            "ВАЖНО: отвечай строго на русском языке.\n"
            "Английские слова запрещены, КРОМЕ тикеров, доменов и названий (например MCOM, swap.coffee).\n"
            "Если не уверен — скажи, что данных недостаточно.\n"
            "Не придумывай факты.\n"
            "Отвечай естественно и по делу; при запросах про токены предпочитай описательный нарратив, а не сухой список фактов.\n"
        )
    return (
        f"{BASE_SYSTEM_PROMPT}\n"
        "IMPORTANT: respond strictly in English.\n"
        "Do not use Russian.\n"
        "If unsure, say you don't have enough data. Do not invent facts.\n"
        "Respond naturally and concisely; for token-related queries prefer descriptive narrative over bare fact restatement.\n"
    )


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


def get_last_user_message_from_history(history: list) -> str | None:
    for item in reversed(history):
        if item.get("role") == "user":
            content = (item.get("content") or "").strip()
            if content:
                return content
    return None

