# AI Backend (FastAPI)

Backend chat API used by the Telegram bot.

## Health Endpoint

- `GET /health` performs dependency checks for:
  - AI -> RAG (`RAG_URL/health`)
  - AI -> LLM provider (`OLLAMA_URL/api/tags` or OpenAI model check)
- Returns `200` when healthy, `503` when degraded, with detailed dependency status in JSON.

## Run Locally

Defaults: **OLLAMA_SWITCH=1** (Ollama starts and model pulls), **OPENAI_SWITCH=0**. No need to set these for local.

```bash
cd ai/backend
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

With Docker locally (Ollama in image, starts on container run):

```bash
docker build -t ai-local ./ai
docker run -p 8000:8000 -e RAG_URL=http://host.docker.internal:8001 -e INNER_CALLS_KEY=your-key ai-local
```

## Environment Variables

Required:

- `INNER_CALLS_KEY` - shared secret expected in `X-API-Key`.

Optional core wiring:

- `RAG_URL` - RAG service base URL (enables `/query` + `/tokens/{symbol}` grounding).

LLM switches (recommended):

- `OLLAMA_SWITCH` - default: `1` (local). Set `0` on server when using OpenAI only so Ollama is not started and not in image.
- `OPENAI_SWITCH` - default: `0`. Set `1` to use OpenAI as primary; when `OLLAMA_SWITCH=1` too, Ollama is used as fallback if OpenAI fails.
- `OPENAI_KEY` - OpenAI API key (required when `OPENAI_SWITCH=1`). Replaces previous `OPENAI_API_KEY` (still accepted).
- `OPENAI_MODEL` - default: `gpt-4o` (no need to set on server if using this model).

Ollama (when `OLLAMA_SWITCH=1`):

- `OLLAMA_URL` - default: `http://127.0.0.1:11434`
- `OLLAMA_MODEL` - default: `qwen2.5:0.5b-instruct`

Copy/paste example (local: Ollama primary):

```env
INNER_CALLS_KEY=change-me-shared-secret
RAG_URL=http://127.0.0.1:8001

OLLAMA_SWITCH=1
OPENAI_SWITCH=0
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:0.5b-instruct
```

Server (OpenAI only, no Ollama in image):

```env
OLLAMA_SWITCH=0
OPENAI_SWITCH=1
OPENAI_KEY=sk-...
# OPENAI_MODEL=gpt-4o is default
```

**If you see OpenAI locally instead of Ollama:** Ensure your local `.env` (e.g. `ai/backend/.env`) does **not** set `OPENAI_SWITCH=1` and does **not** set `OPENAI_KEY`. Remove or comment those lines so defaults apply (Ollama primary). Check startup logs for `primary_provider=ollama`.

## Railway

Recommended service root: `ai/backend`

Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Set `RAG_URL` to the deployed RAG URL and set `INNER_CALLS_KEY` to the same value used by bot/frontend/rag.
