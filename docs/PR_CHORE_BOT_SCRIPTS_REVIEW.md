# PR Review: chore(bot) — add local polling and deploy scripts with minimal envs

**PR title:** `chore(bot): add local polling and deploy scripts with minimal envs`

---

## Verdict: **Worth merging**

Adds developer-facing scripts and docs only. No change to production behavior. Improves local testing and post-deploy webhook setup with minimal env (e.g. `BOT_TOKEN` + `TELEGRAM_WEBHOOK_URL` for deploy).

---

## What this PR likely delivers

| Item | Purpose |
|------|--------|
| **Local polling** | `front/scripts/run-bot-local.js` — run the Grammy bot with `bot.start()` (polling) for local testing without a webhook or ngrok. |
| **Deploy scripts** | `set-telegram-webhook.mjs` — set webhook to Vercel URL after deploy; `delete-telegram-webhook.mjs` — remove webhook (e.g. before local polling). |
| **Minimal envs** | Scripts require only `BOT_TOKEN` (and for set-webhook: `TELEGRAM_WEBHOOK_URL`); optional `TELEGRAM_WEBHOOK_SECRET`. No new env vars for production. |
| **README / docs** | Section(s) on webhook vs local, local testing (polling), and how to run the scripts with minimal env. |

---

## What to check before merge

1. **Scripts are executable / runnable**  
   From `front/`:  
   - `BOT_TOKEN="x" node scripts/delete-telegram-webhook.mjs`  
   - `BOT_TOKEN="x" node scripts/set-telegram-webhook.mjs` (with `TELEGRAM_WEBHOOK_URL`)  
   - `BOT_TOKEN="x" node scripts/run-bot-local.js`  
   All exit 0 with valid token (and URL for set-webhook).

2. **No production impact**  
   - No changes to `api/bot.js` or `bot-service/grammy-bot.js` behavior.  
   - Only new/additive files under `front/scripts/` and doc updates.

3. **Optional: dotenv**  
   - `run-bot-local.js` may try `require('dotenv')`; that’s optional (try/catch).  
   - If the repo doesn’t list `dotenv`, the script should still work with env vars set in the shell.

---

## Summary

| Question | Answer |
|----------|--------|
| **Worth merging?** | **Yes.** Improves DX for local bot testing and for setting the webhook after deploy; minimal env; no risk to production. |
| **Breaking changes?** | No. Additive scripts and documentation. |
| **Follow-up?** | None required. Optional: add `"set-webhook": "node scripts/set-telegram-webhook.mjs"` (and similar) to `front/package.json` scripts for convenience. |

**Recommendation:** Merge once the checks above pass.
