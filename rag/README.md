# RAG Service (Skeleton)

Run locally:
```bash
pip install -r requirements.txt
uvicorn backend.main:app --reload --port 8001
```

**Used by:** The **AI backend** (`ai/backend/main.py`) calls this service when its `RAG_URL` env var is set. The Telegram bot does not call RAG directly. See **[RAG_BOT_AI_INTEGRATION.md](../RAG_BOT_AI_INTEGRATION.md)** for env vars and wiring.

**Deploy to Railway:** Push the repo, deploy the `rag` root directory. The public link is **given by Railway** (Settings → Networking → Generate Domain). Do **not** set that link in this code. Copy that URL and set it as **`RAG_URL`** in the **AI** service’s environment (Railway Variables or .env).

Endpoints:
GET /health
GET /projects
GET /projects/{project_id}
GET /tokens/{symbol}
POST /ingest
POST /query
POST /ingest/projects
POST /ingest/source/allowlist

## Project Knowledge (V1)

This service supports a free-first RAG approach:

- Curated project allowlist
- Public, read-only data
- Fail-open design (no response never blocks AI)

Planned roadmap:
1. Free sources (allowlist, public metadata)
2. Paid APIs (optional adapters)
3. Custom indexer

## How to test in 60 seconds

Assuming the service is running on port 8001:

```bash
curl http://localhost:8001/health
```

```bash
curl http://localhost:8001/projects
```

```bash
curl -X POST http://localhost:8001/ingest/projects \
  -H "Content-Type: application/json" \
  -d @rag/data/projects_allowlist.json
```

```bash
curl -s $RAG_URL/projects/ton
```

```bash
curl -X POST http://localhost:8001/query \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"ton\", \"top_k\": 3}"
```

```bash
curl -s -X POST $RAG_URL/ingest/source/allowlist
```

```bash
curl -s $RAG_URL/tokens/DOGS
```
