#!/usr/bin/env node
/**
 * Run the bot locally with polling (no webhook).
 * Use this for local testing: Telegram updates are fetched via getUpdates.
 *
 * Before running:
 *   1. Set BOT_TOKEN (and optional AI_HEALTH_URL, TELEVERSE_*, APP_URL).
 *   2. If the bot currently has a webhook set, delete it first:
 *      node scripts/delete-telegram-webhook.mjs
 *
 * Then: node scripts/run-bot-local.js
 *   (from front/: node scripts/run-bot-local.js)
 *
 * To use the webhook again (e.g. on Vercel), run set-telegram-webhook.mjs after deploy.
 */
const path = require('path');
try {
  require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
} catch (_) {
  // dotenv optional; use env vars or .env manually
}
const { bot } = require('../bot-service/grammy-bot');

async function main() {
  await bot.api.deleteWebhook({ drop_pending_updates: false });
  console.log('Webhook removed (polling will receive updates).');
  await bot.start({
    onStart: (me) => console.log('Bot running locally (polling). @' + me.username),
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
