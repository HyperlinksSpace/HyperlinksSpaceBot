### Database refactor and extensions (plan)

**Goal**

- Move DB bootstrap into a dedicated `app/database` folder.
- Keep existing `users`, `wallets`, and `pending_transactions` exactly as they are for now.
- Prepare space for new minimal AI chat tables that will be shared by the bot and the TMA client.

**What we just did**

- Created `app/database/start.ts` and moved the current DB bootstrap logic there unchanged:
  - `sql` Neon client export.
  - `ensureSchema()` running the existing migrations for:
    - `users`
    - `wallets`
    - `pending_transactions`
    - their indexes.
- Removed the old `app/db.ts` entry point and updated scripts (e.g. `scripts/migrate-db.ts`) to import from `./database/start` instead.

**Next planned steps (not implemented yet)**

1. **Minimal AI chat tables (shared by bot + TMA)**
   - `chats`:
     - `id` (PK)
     - `chat_id` (FK → `ai_chats(id)`)
     - `external_thread_id` (BIGINT, nullable; e.g. Telegram `message_thread_id`)
     - `last_update_id` (BIGINT) and `active_session_id` (UUID) for concurrency across serverless instances.
   - `ai_messages`:
     - `id` (PK)
     - `thread_id` (FK → `ai_threads(id)`)
     - `role` (`user/assistant/system`)
     - `content` (TEXT)
     - optional `telegram_message_id` and `telegram_update_id` for bot traceability.

2. **Migrations**
   - Extend `runSchemaMigrations()` in `start.ts` with the new tables above in small, append-only blocks.
   - Keep them backwards compatible so existing deployments migrate automatically via `npm run db:migrate`.

This file is just a plan; only the folder creation and `start.ts` changes have been applied so far.

### Database refactor and extensions (plan)

**Goal**

- Move DB bootstrap into a dedicated `app/database` folder.
- Keep existing `users`, `wallets`, and `pending_transactions` exactly as they are for now.
- Prepare space for new minimal AI chat tables that will be shared by the bot and the TMA client.

**What we just did**

- Created `app/database/start.ts` and moved the current `db.ts` logic there unchanged:
  - `sql` Neon client export.
  - `ensureSchema()` running the existing migrations for:
    - `users`
    - `wallets`
    - `pending_transactions`
    - their indexes.
- Turned `app/db.ts` into a small **shim**:
  - `export { sql, ensureSchema } from "./database/start.js";`
  - This keeps all existing imports working while we gradually migrate call sites to import from `./database/start`.

**Next planned steps (not implemented yet)**

1. **User identity unification**
   - Add `telegram_user_id BIGINT UNIQUE` to `users`.
   - Bot and TMA both resolve a single `users` row by `telegram_user_id` so AI chats and wallets are tied to the same person.

2. **Minimal AI chat tables (shared by bot + TMA)**
   - `ai_chats`:
     - `id` (PK)
     - `telegram_user_id` (FK → `users(telegram_user_id)`)
     - `channel` (`'bot' | 'tma'`)
     - `external_chat_id` (BIGINT)
   - `ai_threads`:
     - `id` (PK)
     - `chat_id` (FK → `ai_chats(id)`)
     - `external_thread_id` (BIGINT, nullable; e.g. Telegram `message_thread_id`)
     - `last_update_id` (BIGINT) and `active_session_id` (UUID) for concurrency across serverless instances.
   - `ai_messages`:
     - `id` (PK)
     - `thread_id` (FK → `ai_threads(id)`)
     - `role` (`user/assistant/system`)
     - `content` (TEXT)
     - optional `telegram_message_id` and `telegram_update_id` for bot traceability.

3. **Migrations**
   - Extend `runSchemaMigrations()` in `start.ts` with the new columns/tables above in small, append-only blocks.
   - Keep them backwards compatible so existing deployments migrate automatically via `npm run db:migrate`.

This file is just a plan; only the folder creation and `start.ts` + shim changes have been applied so far.


@app/database/plan.md:27 Why do we need an external chat id here, I think of it as user has a chat (no matter in bot or tma) and threads that come from the both sources, so why not doing so:

Add chat_id in users

Chats
+ user_telegram
+ threads 

Threads
+ thread_id (identifier linking the user to all his chats taken from Telegram and used for tma interactions as well)
+ type (bot/app)
+ last_updated (time)
+ last_update_id (taken from Telegram when in bot)
+ last_message_id (taken from Telegram when in bot)

Messages
+ thread_id
+ role
+ content