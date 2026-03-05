# refactor: Unify API structure, user helpers, Vercel config, and remove SELF_URL

## Summary

This PR groups four related changes: shared user helpers for bot and API, simplified Vercel config and TypeScript ping, unified bot/telegram structure with legacy cleanup, and removal of the `SELF_URL` env in favor of Vercel URL variables. Together they simplify the app layout, reduce duplication, and make deployment configuration lighter.

## Commits

1. **`16996a6` — refactor(app): unify user helpers for bot and api**  
   Single shared `app/api/users.ts` with `normalizeUsername`, `upsertUserFromTma`, and `upsertUserFromBot` backed by `api/db.ts`. Bot webhook, telegram POST handler, and local grammy bot use this module; removed duplicated `app/api/_users.ts` and `app/server/users.ts` so local polling and Vercel serverless share the same user logic.

2. **`cb15afa` — chore(api): simplify vercel function config and move ping to TypeScript**  
   Dropped explicit function overrides from `app/vercel.json` so API routes use Vercel defaults. Replaced `api/ping.js` with `api/ping.ts` that supports Request/Response and legacy `(req, res)` and returns `{ ok: true, ping: true }`.

3. **`3e303ac` — refactor(api): unify bot and telegram structure and remove legacy scripts**  
   Split `api/bot` into a thin route plus `bot/webhook` and shared `bot/grammy` used by both the Vercel webhook and local polling. Moved Telegram POST logic into `api/telegram/post`, added `api/shared/users` and centralized DB access in `api/db`. Removed duplicate webhooks, old JS set-webhook and build-output scripts, and duplicated user helpers to simplify the API layout while keeping behavior the same.

4. **`26a50e0` — chore: remove SELF_URL env, use only Vercel URL vars**  
   Dropped `SELF_URL` from webhook base URL logic. Base URL is now built from `VERCEL_PROJECT_PRODUCTION_URL` or `VERCEL_URL` only. Updated `webhook.ts`, `set-webhook.ts`, `.env.example`, README, and PR doc. Also removed obsolete files: `app/bot/grammy-bot.ts`, `app/bot/webhook.ts`, `app/security.md`, `app/security_plan.md`.

## Changes Made (by area)

### User helpers and DB (commit 1)
- **`app/api/users.ts`**: New shared module with `normalizeUsername`, `upsertUserFromTma`, `upsertUserFromBot` using `api/db.ts`.
- **Removed**: `app/api/_users.ts`, `app/server/users.ts`.
- Bot webhook, telegram POST, and local grammy bot now import from `app/api/users.ts`.

### Vercel and ping (commit 2)
- **`app/vercel.json`**: Removed explicit function overrides; rely on Vercel defaults.
- **`app/api/ping.ts`**: New TypeScript handler (replaces `api/ping.js`); supports Request/Response and legacy (req, res); returns `{ ok: true, ping: true }`.

### Bot and telegram structure (commit 3)
- **`app/api/bot`**: Thin route with shared `bot/webhook` and `bot/grammy`; used by Vercel webhook and local polling.
- **`app/api/telegram/post`**: Heavy Telegram POST logic moved here; **`api/shared/users`** and **`api/db`** for centralized access.
- **Removed**: Duplicate webhooks, old JS set-webhook and build-output scripts, duplicated user helpers.

### SELF_URL removal and cleanup (commit 4)
- **`app/api/bot/webhook.ts`**: Base URL from `VERCEL_PROJECT_PRODUCTION_URL` or `VERCEL_URL` only; no `SELF_URL`; comments and `expected_url` fallback updated.
- **`app/scripts/set-webhook.ts`**: Same Vercel-only base URL; comment and env log no longer mention SELF_URL.
- **`app/.env.example`**: Removed `SELF_URL` entry.
- **Docs**: `app/README.md` and `docs/PULL_REQUEST_Dereal1.md` updated for Vercel-only URL and `BOT_TOKEN`-only deploy.
- **Removed**: `app/bot/grammy-bot.ts`, `app/bot/webhook.ts`, `app/security.md`, `app/security_plan.md`.

## Impact

- **Single user/DB path**: Bot and API use one user helper and DB layer.
- **Simpler Vercel config**: No custom function overrides; ping in TypeScript.
- **Clearer API layout**: Bot vs telegram vs shared code is separated; legacy scripts removed.
- **Simpler deployment**: No `SELF_URL`; webhook URL from `VERCEL_PROJECT_PRODUCTION_URL` or `VERCEL_URL` only.
