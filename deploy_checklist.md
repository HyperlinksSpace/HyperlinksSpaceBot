# Deploy Checklist (Railway)

Deploy in this order: `RAG -> AI -> Bot`.

## 1) RAG Service

- Root directory: `rag/backend`
- Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

- Required envs:

```env
TOKENS_API_URL=https://tokens.swap.coffee
```

- Optional envs:

```env
TOKENS_API_KEY=
RAG_STORE_PATH=rag_store.json
PROJECTS_STORE_PATH=projects_store.json
TOKENS_STORE_PATH=tokens_store.json
```

- Verify health:

```bash
curl -s https://<rag-domain>/health
```

## 2) AI Service

- Root directory: `ai/backend`
- Start command:

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

- Required envs:

```env
API_KEY=change-me-shared-secret
RAG_URL=https://<rag-domain>
LLM_PROVIDER=ollama
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b
```

- Optional fallback:

```env
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4o-mini
```

- Verify endpoint:

```bash
curl -s https://<ai-domain>/
```

## 3) Bot Service

- Root directory: `bot`
- Start command:

```bash
python bot.py
```

- Required envs:

```env
BOT_TOKEN=123456:telegram-token
DATABASE_URL=postgresql://user:pass@host:5432/db
AI_BACKEND_URL=https://<ai-domain>
API_KEY=change-me-shared-secret
```

- Optional env:

```env
APP_URL=https://<frontend-domain>
```

## Final Smoke Test

After all 3 are up, send in Telegram:

1. `$DOGS`
2. `что такое DOGS?`
3. `$TON`

Expected:

- RAG receives `/tokens/{symbol}` requests and returns `200` for valid symbols.
- AI backend does not show `RAG verification failed` for these requests.
- Bot returns clean replies from AI backend stream.
