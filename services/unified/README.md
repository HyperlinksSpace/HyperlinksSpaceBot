# Unified Service (Milestone 1)

This folder contains the first unified runtime skeleton for bot + ai + rag.

Current status:
- `UNIFIED_MODE=forward` (default): forwarding stubs to existing services.
- `UNIFIED_MODE=local`: reserved for future in-process implementation.

## Endpoints

- `GET /health`
- `POST /auth/telegram` -> forwards to bot `/auth/telegram`
- `POST /ai/chat` -> forwards to ai `/api/chat`
- `POST /api/chat` -> compatibility alias for `/ai/chat`
- `POST /rag/query` -> forwards to rag `/query`
- `POST /query` -> compatibility alias for `/rag/query`

## Run local

```bash
cd services/unified
python -m pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8090
```

## Environment

- `UNIFIED_MODE` (`forward` by default)
- `UNIFIED_FORWARD_TIMEOUT_SECONDS` (`30` by default)
- `UNIFIED_FORWARD_CONNECT_TIMEOUT_SECONDS` (`5` by default)
- `BOT_BASE_URL` (`http://127.0.0.1:8080` by default)
- `AI_BASE_URL` (`http://127.0.0.1:8000` by default)
- `RAG_BASE_URL` (`http://127.0.0.1:8001` by default)
- `INNER_CALLS_KEY` (forwarded to upstream if request has no `X-API-Key`)
