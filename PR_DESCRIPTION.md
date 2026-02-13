## Summary

This PR prepares the stack for shipping with env-driven LLM routing, clean service boundaries, and Railway deployment guidance.

### Included changes

- AI backend:
  - Added env-based LLM routing (`LLM_PROVIDER`) with Ollama default and optional OpenAI fallback.
  - Removed hardcoded model path; model/provider selected from env in one place.
- Bot:
  - Kept bot as thin transport layer to AI backend (`/api/chat` + `X-API-Key`).
  - Removed ticker-specific local prompt branching.
- Deploy/docs:
  - Added copy/paste env examples and Railway 3-service deployment docs.
  - Added smoke test scripts and env templates.

## Railway Deploy Order

1. **RAG** (FastAPI)
2. **AI backend** (FastAPI)
3. **Bot** (worker)

## Required Env Vars Per Service

### Service A: RAG

```env
TOKENS_API_URL=https://tokens.swap.coffee
# optional: TOKENS_API_KEY
```

Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

### Service B: AI backend

```env
API_KEY=change-me-shared-secret
RAG_URL=https://<rag-domain>
LLM_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b
# optional:
# OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o-mini
```

Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

### Service C: Bot

```env
BOT_TOKEN=123456:telegram-token
DATABASE_URL=postgresql://user:pass@host:5432/db
AI_BACKEND_URL=https://<ai-domain>
API_KEY=change-me-shared-secret
# optional: APP_URL
```

Start command:

```bash
python bot.py
```

## How To Smoke Test

### Telegram checks

Send:

1. `$DOGS`
2. `что такое DOGS?`
3. `$TON`

Confirm:

- RAG receives `/tokens/{symbol}` and returns `200` for valid symbols.
- AI backend does not log `RAG verification failed` for those requests.
- Bot replies cleanly.

### Scripted checks

Bash:

```bash
export API_KEY=...
./smoke_test.sh
```

PowerShell:

```powershell
$env:API_KEY="..."
.\smoke_test.ps1
```
