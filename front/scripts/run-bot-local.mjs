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
