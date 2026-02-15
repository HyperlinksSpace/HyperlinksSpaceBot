This is a monorepo containing multiple services.

## Local host deploy

Start

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "/c/1/HyperlinksSpaceBot/start_local.ps1"
```

Stop

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "/c/1/HyperlinksSpaceBot/stop_local.ps1"

## Repository Structure

```
q1cbbot/
├── front/          # Flutter frontend
├── ai/             # AI chat backend (FastAPI, provider via env)
├── bot/            # Telegram bot (worker)
└── rag/            # RAG server (FastAPI)
```

## Services

### Frontend (`front/`)
- **Technology**: Flutter Web
- **Purpose**: Telegram Mini App UI
- **Deployment**: Railway (configured in `front/railway.json`)

### AI Service (`ai/`)
- **Technology**: FastAPI + env-configurable LLM provider (`ollama` default)
- **Purpose**: AI chat API
- **Entry point**: `ai/backend/main.py`

### Bot (`bot/`)
- **Technology**: python-telegram-bot
- **Purpose**: Telegram interface; calls AI backend only

### RAG Server (`rag/`)
- **Technology**: FastAPI
- **Purpose**: Verified token/project retrieval for AI grounding

## Railway Deploy

Deploy as 3 services in this order: `rag` -> `ai` -> `bot`.

### Service A: RAG (FastAPI)

- **Root directory:** `rag/backend`
- **Start command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
- **Health endpoint:** `/health`

Env vars (copy/paste):

```env
TOKENS_API_URL=https://tokens.swap.coffee
# optional:
# TOKENS_API_KEY=
# RAG_STORE_PATH=rag_store.json
# PROJECTS_STORE_PATH=projects_store.json
# TOKENS_STORE_PATH=tokens_store.json
```

### Service B: AI backend (FastAPI)

- **Root directory:** `ai/backend`
- **Start command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
- **Required wiring:** `RAG_URL` must point to Service A URL

Env vars (copy/paste):

```env
API_KEY=change-me-shared-secret
RAG_URL=https://your-rag-service.up.railway.app

LLM_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b

# optional fallback provider:
# OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o-mini
```

Notes:
- `LLM_PROVIDER=ollama` is the default.
- In production, Railway usually should point `OLLAMA_URL` to an external Ollama host (VPS/GPU box), not local Railway runtime.

### Service C: Bot (Worker)

- **Root directory:** `bot`
- **Start command:** `python bot.py`
- Bot should only call AI backend: `POST {AI_BACKEND_URL}/api/chat` with `X-API-Key`.

Env vars (copy/paste):

```env
BOT_TOKEN=123456:telegram-token
DATABASE_URL=postgresql://user:pass@host:5432/db
AI_BACKEND_URL=https://your-ai-service.up.railway.app
API_KEY=change-me-shared-secret
# optional:
# APP_URL=https://your-frontend-domain
```

## Local Verification Checklist

After starting `rag`, `ai`, and `bot` locally:

1. Send `$DOGS`
2. Send `что такое DOGS?`
3. Send `$TON`

Confirm:
- RAG logs show `/tokens/{symbol}` with `200`.
- AI backend has no `RAG verification failed` for those requests.
- Bot replies cleanly from AI backend responses.
