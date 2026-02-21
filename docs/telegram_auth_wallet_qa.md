# Telegram Auth + Wallet Ensure QA Checklist

This checklist verifies the end-to-end flow:

Telegram WebApp initData -> `/auth/telegram` server-side verification -> user upsert -> atomic wallet claim -> frontend boot gate.

## Preconditions

- Bot backend is running and reachable by the frontend
- `BOT_TOKEN` is set in backend environment
- `APP_URL` points to the frontend
- Users DB is available (backend can connect)
- (Optional) `X-API-Key` is configured if required by middleware for certain routes (note: `/auth/telegram` should not require it)

## Flow A: Open inside Telegram (expected success)

1. Open the bot in Telegram.
2. Tap **Run app** (URL button).

Expected:
- App shows a loading spinner briefly, then loads `MainPage`.
- Network call: `POST /auth/telegram` returns `200`.
- Response body includes:
  - `ok: true`
  - `user.username` (normalized)
  - `wallet_status` ∈ `{ "assigned", "already_assigned" }`
  - `newly_assigned` boolean

## Flow B: Repeat open inside Telegram (idempotency)

1. Close the app.
2. Tap **Run app** again.

Expected:
- `POST /auth/telegram` returns `200`.
- `wallet_status` is usually `"already_assigned"` (may be `"assigned"` only on the first ever run).
- App loads `MainPage` normally.

## Flow C: Open outside Telegram (expected block)

1. Copy the `APP_URL`.
2. Open it in a normal browser (Chrome/Safari) outside Telegram.

Expected:
- Frontend shows a blocking message:
  - "Open this app from inside Telegram."
- No navigation to `MainPage`.
- No crash loops.

## Flow D: Invalid initData (expected 401)

Method:
- Replay with a modified `initData` value (tamper hash) or send an empty string.

Expected:
- Backend returns `401` with `{"ok": false, "error": "invalid_initdata"}`.
- Frontend shows the blocking auth error and offers Retry.

## Flow E: Username missing (expected 400)

Note: Telegram users can have no username.

Expected:
- Backend returns `400` with `{"ok": false, "error": "username_required"}`.
- Frontend shows a user-friendly message telling the user to set a Telegram username.

## Flow F: DB unavailable (expected 503)

Method:
- Stop DB or break DB connectivity.

Expected:
- Backend returns `503` with `{"ok": false, "error": "db_unavailable"}`.
- Frontend shows a temporary service error and offers Retry.

## Quick log sanity

Backend should emit a structured line (no raw initData):
- `auth_telegram username=<...> wallet_status=<...>`

## Notes / Hardening Later

- Replace `Access-Control-Allow-Origin: *` with an allowlist (e.g., `ALLOWED_ORIGINS`) once production domains are fixed.
- Consider basic rate limiting on `POST /auth/telegram`.
- Consider moving wallet identity from `username` to `telegram_id` as the long-term stable key (username remains display/mutable).
