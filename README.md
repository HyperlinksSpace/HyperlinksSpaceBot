*Special note: now temporarily main development is in [`./app`](./app) folder. After refactor it'll be in root.*

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