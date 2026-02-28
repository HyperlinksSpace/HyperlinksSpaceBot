/**
 * Local run: polling (getUpdates). Only BOT_TOKEN needed.
 * Run: BOT_TOKEN=xxx node scripts/run-bot-local.js
 * Do not run with the same token while webhook is set in production.
 */
const path = require('path');
try {
  require('dotenv').config({ path: path.join(__dirname, '../.env') });
} catch (_) {}
const { createBot } = require('../bot/grammy-bot');

const token = (process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN || '').trim();
if (!token) {
  console.error('Missing BOT_TOKEN (or TELEGRAM_BOT_TOKEN)');
  process.exit(1);
}

async function main() {
  const bot = createBot(token);
  await bot.api.deleteWebhook();
  await bot.start();
  console.log('Bot running locally (getUpdates). Press Ctrl+C to stop.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
