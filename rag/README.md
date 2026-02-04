# RAG Service (Skeleton)

Run locally:
pip install -r requirements.txt
uvicorn backend.main:app --reload --port 8001

Endpoints:
GET /health
POST /ingest
POST /query

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
