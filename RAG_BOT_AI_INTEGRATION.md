# RAG + AI + Bot Integration

## Architecture

```text
User (Telegram)
  -> Bot (bot/bot.py)
     -> POST {AI_BACKEND_URL}/api/chat + X-API-Key
        -> AI backend (ai/backend/main.py)
           -> optional RAG calls:
              - GET {RAG_URL}/tokens/{symbol}
              - GET {RAG_URL}/query?q=...
           -> LLM provider selected by env:
              - ollama (default)
              - openai (optional)
```

Rules:
- Bot never calls RAG directly.
- Bot does not run local LLM logic.
- AI backend owns ticker/RAG logic and final prompting.

## Service Setup (Railway)

Deploy in order: `RAG` -> `AI` -> `Bot`.

### 1) RAG service

- Root: `rag/backend`
- Start:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

- Health: `GET /health`

Env:

```env
TOKENS_API_URL=https://tokens.swap.coffee
# optional: TOKENS_API_KEY=
```

### 2) AI backend service

- Root: `ai/backend`
- Start:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Env:

```env
API_KEY=change-me-shared-secret
RAG_URL=https://your-rag.up.railway.app

LLM_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b

# optional fallback:
# OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o-mini
```

Note: In Railway production, point `OLLAMA_URL` to an external Ollama host (VPS/GPU box) if needed.

### 3) Bot worker

- Root: `bot`
- Start:

```bash
python bot.py
```

Env:

```env
BOT_TOKEN=123456:telegram-token
DATABASE_URL=postgresql://user:pass@host:5432/db
AI_BACKEND_URL=https://your-ai.up.railway.app
API_KEY=change-me-shared-secret
# optional: APP_URL=https://your-frontend-domain
```

## Local Smoke Test

1. Start RAG on `:8001`
2. Start AI on `:8000` with `RAG_URL=http://127.0.0.1:8001`
3. Start Bot with `AI_BACKEND_URL=http://127.0.0.1:8000`
4. Send:
   - `$DOGS`
   - `что такое DOGS?`
   - `$TON`

Expected:
- RAG `/tokens/...` returns 200 for valid symbols.
- AI backend does not log `RAG verification failed` for those normal cases.
- Bot replies from AI backend stream.
