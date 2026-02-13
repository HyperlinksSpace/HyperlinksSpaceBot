# Telegram Bot (Worker)

Bot service that relays user messages to the AI backend.

## Run Locally

```bash
cd bot
pip install -r requirements.txt
python bot.py
```

## Environment Variables

Required:

- `BOT_TOKEN`
- `DATABASE_URL`
- `AI_BACKEND_URL`
- `API_KEY` (must match AI backend `API_KEY`)

Optional:

- `APP_URL` (used in `/start` button)

Example:

```env
BOT_TOKEN=123456:telegram-token
DATABASE_URL=postgresql://user:pass@host:5432/db
AI_BACKEND_URL=http://127.0.0.1:8000
API_KEY=change-me-shared-secret
APP_URL=https://your-frontend-domain
```

## Railway

- Root directory: `bot`
- Start command: `python bot.py`

The bot calls only:

- `POST {AI_BACKEND_URL}/api/chat`
- Header `X-API-Key: {API_KEY}`
