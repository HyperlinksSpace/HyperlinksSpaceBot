This is a monorepo containing multiple services.

## How to fork and contribute?

1.Install GitHub CLI and authorize to GitHub from cli for instant work

```
winget install --id GitHub.cli
gh auth login
``

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

Create a bot using @BotFather. Copy bot token and set it in `shell/start.ps1` (environment block near the top).

Run the script to start on localhost (logs show in RAG/AI/BOT/FRONT windows by default)

```
sh ./start.sh
```

Run the script to stop on localhost

```
sh ./stop.sh
```

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
