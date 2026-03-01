import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { startPolling } = require('../bot-service/grammy-bot');

const token = (process.env.BOT_TOKEN || '').trim();
if (!token) {
  console.error('Missing BOT_TOKEN');
  process.exit(1);
}

console.warn('[bot:local] Using polling mode (getUpdates).');
console.warn('[bot:local] Do not run with the same token while webhook is active in prod.');

await startPolling();
console.log('[bot:local] Polling started. Press Ctrl+C to stop.');

import { startPolling } from "../../packages/bot/dist/index.js";

const BOT_TOKEN = process.env.BOT_TOKEN;
if (!BOT_TOKEN) {
  console.error("BOT_TOKEN is required");
  process.exit(1);
}

console.log("Starting bot in polling mode (local)...");
startPolling({ BOT_TOKEN }, { logger: (e) => console.log(JSON.stringify(e)) });
