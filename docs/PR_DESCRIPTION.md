## PR Title

`feat(bot): add Vercel JS webhook gateway with Televerse forwarding skeleton`

## Summary

This PR adds a production-safe Telegram webhook gateway in `front/api/bot.js` and isolates bot logic into `front/bot-service/*`.
The gateway handles core commands locally (`/start`, `/help`, `/ping`), applies strict webhook safety checks, and can optionally forward sanitized updates to a Televerse (Dart) downstream service.

## Confirmed Direction

- JS webhook receiver on Vercel (thin entrypoint)
- Televerse service handles richer logic downstream
- Gateway remains reliable even when AI/downstream are unavailable

## Gateway Contract

- `GET /api/bot`
  - Health/status for gateway wiring.
- `POST /api/bot`
  - Verifies `X-Telegram-Bot-Api-Secret-Token` (when configured).
  - Rejects oversized payloads.
  - Validates parsed JSON update.
  - Responds `200 { ok: true }` immediately after validation (antifragile ACK behavior).
  - Processes update best-effort asynchronously.

## Core Behavior

- `/start`
  - Uses bounded AI health probe:
    - `AI_HEALTH_TIMEOUT_MS` default `1200`
    - clamped to `200..1500`
    - cached for short TTL (`AI_HEALTH_CACHE_TTL_MS`, default `30000`)
  - AI up => welcome suggests prompts
  - AI down => safe welcome without prompt suggestion
- `/help` and `/ping` handled locally in gateway
- Non-core text messages optionally forwarded to Televerse via internal endpoint

## Security and Reliability

- Secret-token verification (`401` on mismatch)
- Payload size limit (`TELEGRAM_BODY_LIMIT_BYTES`, default `262144`)
- Structured sanitized logs (`telegram_webhook_error`, `update_id`, `chat_id`, `update_kind`)
- No raw payload logging in error path

## Televerse Forwarding Contract (Skeleton)

Gateway forwards a reduced envelope to:
- `POST {TELEVERSE_BASE_URL}/internal/process-update`
- Header: `X-Internal-Key: {TELEVERSE_INTERNAL_KEY}`

Envelope shape:

```json
{
  "update_id": 123,
  "chat_id": 1,
  "user_id": 2,
  "text": "hi",
  "message_id": 10,
  "is_command": false,
  "command": null,
  "timestamp": 1700000000
}
```

## Files Added

- `front/api/bot.js`
- `front/bot-service/config.js`
- `front/bot-service/logger.js`
- `front/bot-service/text.js`
- `front/bot-service/ai-health.js`
- `front/bot-service/telegram.js`
- `front/bot-service/downstream.js`
- `front/bot-service/router.js`
- `front/scripts/set-telegram-webhook.mjs`
- `front/scripts/delete-telegram-webhook.mjs`

## Files Updated

- `front/vercel.json`
- `front/README.md`

## Manual Smoke Checklist

1. Set env vars (`BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, optional AI/Televerse vars).
2. Deploy front to Vercel.
3. Run `node front/scripts/set-telegram-webhook.mjs` with `TELEGRAM_WEBHOOK_URL=https://<domain>/api/bot`.
4. Send `/start` with healthy AI endpoint => prompt suggestion appears.
5. Break `AI_HEALTH_URL` => `/start` safe fallback without prompt suggestion.
6. Send wrong secret header => `401`.
7. Send malformed/oversized request => rejection path works.

## Notes

- This PR intentionally follows the existing `front/api/*.js` Vercel style for fast merge and single-root deployment.
- `apps/bot` prototype is not part of this PR scope.
