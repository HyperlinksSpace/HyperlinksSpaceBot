## ENVS

Set env vars per service in remote deploy as follows.

### Bot service (`bot/bot.py`)

- Required: `BOT_TOKEN`
- Required: `INNER_CALLS_KEY` - must match frontend + AI + RAG
- Required: `AI_BACKEND_URL` - public/internal URL of AI backend service
- Required: `APP_URL` - public HTTPS URL of deployed frontend (Telegram Mini App URL)
- Optional: `HTTP_PORT` (or platform `PORT`)
- Optional compatibility aliases: `SELF_API_KEY`, `API_KEY`, `AI_KEY`
- Optional: `DATABASE_URL` (enable persistence), `HTTP_API_TIMEOUT_SECONDS`, `EDIT_INTERVAL_SECONDS` (stream edit throttle, default `1`), `HTTP_HOST`

### AI service (`ai/backend/main.py`)

- Required: `INNER_CALLS_KEY` - same shared key as bot/frontend/rag
- Required: `RAG_URL` - URL of RAG backend service
- Optional provider switch: `LLM_PROVIDER=ollama|openai`
- If `LLM_PROVIDER=openai`: `OPENAI_API_KEY` (required), `OPENAI_MODEL` (optional, default `gpt-4o-mini`)
- If `LLM_PROVIDER=ollama`: `OLLAMA_URL`, `OLLAMA_MODEL`
- Optional compatibility alias: `API_KEY`
- Optional: platform `PORT`

### RAG service (`rag/backend/main.py`)

- Required: `INNER_CALLS_KEY` - same shared key as bot/frontend/ai
- Optional: `COFFEE_URL` (default `https://tokens.swap.coffee`, replaces old `TOKENS_API_URL`)
- Optional: `COFFEE_KEY` (swap.coffee API key, if required by provider limits)
- Optional: `TOKENS_VERIFICATION`
- Optional storage paths: `RAG_STORE_PATH`, `PROJECTS_STORE_PATH`

### Frontend (`front/`)

- Required at build/run: `BOT_API_URL` - bot HTTP API base URL
- Required at build/run: `INNER_CALLS_KEY` - same shared key as bot/AI/RAG
- Optional compatibility alias: `BOT_API_KEY`
- Optional (theme): `THEME`