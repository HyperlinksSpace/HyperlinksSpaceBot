# AI Backend (FastAPI)

Backend chat API used by the Telegram bot.

## Health Endpoint

- `GET /health` performs dependency checks for:
  - AI -> RAG (`RAG_URL/health`)
  - AI -> LLM provider (`OLLAMA_URL/api/tags` or OpenAI model check)
- Returns `200` when healthy, `503` when degraded, with detailed dependency status in JSON.

## Run Locally

```bash
cd ai/backend
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

## Environment Variables

Required:

- `INNER_CALLS_KEY` - shared secret expected in `X-API-Key`.

Optional core wiring:

- `RAG_URL` - RAG service base URL (enables `/query` + `/tokens/{symbol}` grounding).

LLM provider routing:

- `LLM_PROVIDER` - default: `openai`
- `OLLAMA_URL` - default: `http://127.0.0.1:11434`
- `OLLAMA_MODEL` - default: `qwen2.5:1.5b`
- `OPENAI_API_KEY` - required only when `LLM_PROVIDER=openai`
- `OPENAI_MODEL` - default: `gpt-4o-mini`
- `OPENAI_MAX_TOKENS` - default: `600`
- `OPENAI_TEMPERATURE` - default: `0.3`
- `OPENAI_TIMEOUT_SECONDS` - default: `30`

URL normalization for service base URLs:

- `RAG_URL`, `OLLAMA_URL`, and `COCOON_CLIENT_URL` accept plain hostnames/domains.
- If protocol is omitted, backend auto-prefixes `https://`.
- Trailing `/` is trimmed automatically.

Copy/paste example:

```env
INNER_CALLS_KEY=change-me-shared-secret
RAG_URL=http://127.0.0.1:8001

LLM_PROVIDER=openai
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b

# optional:
# OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o-mini
# OPENAI_MAX_TOKENS=600
# OPENAI_TEMPERATURE=0.3
# OPENAI_TIMEOUT_SECONDS=30
```

## Railway

Recommended service root: `ai/backend`

Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Set `RAG_URL` to the deployed RAG URL and set `INNER_CALLS_KEY` to the same value used by bot/frontend/rag.
