**HyperlinksSpaceBot** is a Telegram Mini App for the TON ecosystem: a wallet-style UI (Feed, Swap, Trade, Send, Get, Apps, Coins) plus an AI assistant in the bottom app bar and telegram bot that answers questions using RAG-grounded token and project data (e.g. `$DOGS`, `$TON`). The monorepo includes a Flutter web frontend, a Python Telegram bot with HTTP API (gateway and “Run app” entry point), an AI chat backend (FastAPI), and a RAG service for token/project retrieval from sources like swap.coffee. The AI backend uses Ollama or OpenAI for generation. Run locally with `start.sh`, or deploy bot, AI, and RAG to Railway and the frontend to Vercel.

## How to fork and contribute?

1. Install GitHub CLI and authorize to GitHub from CLI for instant work

```
winget install --id GitHub.cli
gh auth login
```

2. Fork the repo, clone it and create a new branch and switch to it

```
gh repo fork https://github.com/HyperlinksSpace/HyperlinksSpaceBot.git --clone
git checkout -b new-branch-for-an-update
git switch -c new-branch-for-an-update
```

3. After making a commit, make a pull request, gh tool will already know the upstream remote

```
gh pr create --title "My new PR" --body "It is my best PR"
```

## Localhost deploy

Create a bot using @BotFather. Duplicate .env.example, renaming it to .env and copy there the bot token created.

Run the script to start on localhost (logs show in RAG/AI/BOT/FRONT windows by default)

```
sh ./start.sh
```

Run the script to stop on localhost

```
sh ./stop.sh
```

## Deploy

### Prerequisites

1. **Railway** – for bot, AI, and RAG backends  
   - Create an account at [railway.app](https://railway.app)  
   - Install CLI: `npm i -g @railway/cli`  
   - Log in: `railway login`  
   - Configure each service (bot, ai, rag) in the Railway dashboard and link them with `railway link` from each directory

2. **Vercel** – for the Flutter web frontend  
   - Create an account at [vercel.com](https://vercel.com)  
   - Install CLI: `npm i -g vercel`  
   - Log in: `vercel login`  
   - Ensure Flutter is installed (required for `front/deploy.sh`)

### Deploy workflow

**Start deploy** – opens four terminals and deploys in parallel:

```
sh ./launch.sh
```

This runs:

- **BOT DEPLOY** – `railway up` from `bot/`
- **AI DEPLOY** – `railway up` from `ai/`
- **RAG DEPLOY** – `railway up` from `rag/`
- **FRONT DEPLOY** – `sh deploy.sh` from `front/` (builds Flutter web, deploys to Vercel)

Each deploy runs in its own window. Wait until all four complete successfully.

**Close deploy terminals** – after deploys finish, close the deploy windows:

```
sh ./success.sh
```

This closes the BOT/AI/RAG/FRONT DEPLOY terminals and any leftover deploy child processes (e.g. `railway up`, `deploy.sh`).

*With `commands` loaded (direnv or `source commands`), you can run `launch` and `success` instead of the full paths.*

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

## Repository Structure

```
HyperlinksSpaceBot/
├── ai/                    # AI backend (FastAPI)
│   └── backend/
├── bot/                   # Telegram bot + bot HTTP API
├── front/                 # Flutter web frontend (Mini App UI)
├── rag/                   # RAG backend (FastAPI)
│   └── backend/
├── docs/                  # Project docs
├── start.sh               # Root wrapper -> shell/start.ps1
├── stop.sh                # Root wrapper -> shell/stop.ps1
├── smoke.sh               # Root wrapper -> shell/smoke.ps1
└── shell/                 # PowerShell implementations
```

## Runtime Architecture

Local stack runs these services:

- `rag/backend` (FastAPI): token/project retrieval for grounding
- `ai/backend` (FastAPI): chat backend that calls RAG and LLM provider
- `bot/bot.py`:
  - Telegram bot polling worker
  - HTTP API server on port `8080` for frontend calls
- `front` (Flutter web-server): Mini App frontend on port `3000`
- `ollama` (optional external/local process): default LLM provider in local mode

Request path in local mode:

`Frontend -> Bot HTTP API (:8080) -> AI backend (:8000) -> RAG (:8001) [+ Ollama/OpenAI]`

## Local Scripts

### `start.sh` / `shell/start.ps1`

Starts local stack, writes/streams logs, performs readiness checks, and opens frontend in browser when ready.

Supported switches:

- `-Reload` - enables `uvicorn --reload` for AI and RAG
- `-ForegroundBot` - runs bot in current terminal (Ctrl+C stops services)
- `-StopOllama` - stops existing Ollama listener during pre-cleanup
- `-OpenLogWindows` - opens separate log-tail windows for services (only when using file logs)
- `-NoServiceWindowLogs` - log to files instead of service process windows (default: logs in service windows)

### `stop.sh` / `shell/stop.ps1`

Stops the local stack robustly by:

- killing listeners on service ports (`3000`, `8000`, `8001`, `8080`, optionally `11434`)
- killing known bot/flutter/backend processes
- killing repo-scoped leftover runtime processes and log-tail windows

Switch:

- `-KeepOllama` - keeps `11434` listener alive

## Local Ports and Health Checks

- `3000` - frontend (`http://127.0.0.1:3000`)
- `8000` - AI backend
- `8001` - RAG backend
- `8080` - bot HTTP API (`/health`)
- `11434` - Ollama API (when using `LLM_PROVIDER=ollama`)

`start.sh` reports readiness for:

- RAG `/health`
- AI root endpoint
- Bot API `/health`
- Frontend availability
- Ollama model presence (when Ollama provider is active)

## Frontend Deploy Flow

Current frontend deploy helper scripts in `front/` are Vercel-oriented:

- `front/deploy.sh`
- `front/deploy.bat`

`start.sh` also prints this flow after startup:

1. `cd front`
2. `bash deploy.sh` (or `.\deploy.bat` on Windows)

## Quick Local Verification

After stack startup:

1. Open `http://127.0.0.1:3000`
2. Check bot API health: `http://127.0.0.1:8080/health`
3. In Telegram, run `/start` and tap "Run app"
4. Send test prompts in chat (for example `$DOGS`, `$TON`)

Expected:

- frontend loads and can call bot API
- bot answers without API key errors
- AI backend responds and can access RAG for token lookups
