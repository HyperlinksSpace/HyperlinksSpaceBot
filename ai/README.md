# AI Backend (FastAPI)

Backend chat API used by the Telegram bot.

## Run Locally

```bash
cd ai/backend
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

## Environment Variables

Required:

- `API_KEY` - shared secret expected in `X-API-Key`.

Optional core wiring:

- `RAG_URL` - RAG service base URL (enables `/query` + `/tokens/{symbol}` grounding).

LLM provider routing:

- `LLM_PROVIDER` - default: `ollama`
- `OLLAMA_URL` - default: `http://127.0.0.1:11434`
- `OLLAMA_MODEL` - default: `qwen2.5:1.5b`
- `OPENAI_API_KEY` - required only when `LLM_PROVIDER=openai`
- `OPENAI_MODEL` - default: `gpt-4o-mini`

Copy/paste example:

```env
API_KEY=change-me-shared-secret
RAG_URL=http://127.0.0.1:8001

LLM_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b

# optional:
# OPENAI_API_KEY=
# OPENAI_MODEL=gpt-4o-mini
```

## Railway

Recommended service root: `ai/backend`

Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Set `RAG_URL` to the deployed RAG URL and set `API_KEY` to the same value used by the bot.
