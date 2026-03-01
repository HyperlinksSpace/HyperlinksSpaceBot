## PR Title

`chore(bot): stabilize front runtime and pause Televerse hot-path dependency`

## Summary

This PR applies a low-risk stabilization pass to the current `front/` Telegram bot runtime.
It keeps webhook/API contracts unchanged, removes Televerse from active message handling, and preserves the portable bot interface (`createBot/getBot/startPolling`) used by both webhook and local polling modes.

## What Changed

- Kept webhook behavior stable in `front/api/bot.js`:
  - Same endpoint and validation semantics (`401`, `413`, `400`, ACK `200`).
  - Same ACK-first async processing model.
- Paused Televerse runtime dependency:
  - `front/bot-service/grammy-bot.js` no longer forwards text messages to downstream Televerse.
  - Non-command text now deterministically replies with local fallback.
- Preserved/kept observability:
  - `bot_command`
  - `ai_probe_latency`
  - `bot_handler_latency`
  - `telegram_webhook_error`
- Removed Televerse env usage from active config path:
  - `TELEVERSE_BASE_URL` / `TELEVERSE_INTERNAL_KEY` are no longer required by active runtime.
- Added compatibility headers in legacy helper files (`downstream.js`, `router.js`) to mark them as paused/not active.
- Updated docs (`front/README.md`) to reflect current runtime behavior and added portability notes for future `app/` migration.

## Public Contract (Unchanged)

- `GET /api/bot` for health/info.
- `POST /api/bot`:
  - Secret header check when configured.
  - Payload size guard.
  - Invalid body guard.
  - Immediate `200 { ok: true }` ACK after validation.
  - Async bot processing after ACK.

## Runtime Behavior

- `/start`: bounded AI health probe and safe fallback welcome if AI is unavailable.
- `/help`: command list.
- `/ping`: `pong`.
- Other text: local deterministic fallback (`Use /help for available commands.`).

## Manual Verification

1. `GET /api/bot` returns `200`.
2. `POST /api/bot` wrong secret returns `401`.
3. Oversized request returns `413`.
4. Invalid/non-object body returns `400`.
5. Valid update returns immediate `200` and is processed asynchronously.
6. `/start` with AI up/down returns expected adaptive message.
7. `/help` and `/ping` still respond correctly.
8. Duplicate `update_id` is dropped in warm runtime and logged.

## Notes

- No new env vars.
- No route/path changes.
- No deploy-surface expansion.
- Bot modules remain portable for future migration to a new `app/` folder (`front/api/bot.js` thin wrapper + `front/bot-service/*` core logic).
