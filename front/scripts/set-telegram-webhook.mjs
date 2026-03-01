#!/usr/bin/env node
/**
 * Set Telegram webhook URL for the bot.
 * Run after deploy so Telegram sends updates to your Vercel endpoint.
 *
 * Env:
 *   BOT_TOKEN or TELEGRAM_BOT_TOKEN - required
 *   TELEGRAM_WEBHOOK_URL - required, e.g. https://your-app.vercel.app/api/bot
 *   TELEGRAM_WEBHOOK_SECRET - optional, same as in Vercel env
 */
const token = (process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN || '').trim();
const url = (process.env.TELEGRAM_WEBHOOK_URL || '').trim();

if (!token) {
  console.error('Error: Set BOT_TOKEN or TELEGRAM_BOT_TOKEN');
  process.exit(1);
}
if (!url) {
  console.error('Error: Set TELEGRAM_WEBHOOK_URL (e.g. https://your-app.vercel.app/api/bot)');
  process.exit(1);
}

const params = new URLSearchParams({ url });
if (process.env.TELEGRAM_WEBHOOK_SECRET) {
  params.set('secret_token', process.env.TELEGRAM_WEBHOOK_SECRET);
}

const apiUrl = `https://api.telegram.org/bot${token}/setWebhook?${params.toString()}`;

const res = await fetch(apiUrl);
const data = await res.json().catch(() => ({}));

if (!data.ok) {
  console.error('Telegram API error:', data.description || res.statusText);
  process.exit(1);
}

console.log('Webhook set successfully.');
console.log('URL:', url);
if (process.env.TELEGRAM_WEBHOOK_SECRET) console.log('Secret token: set');
