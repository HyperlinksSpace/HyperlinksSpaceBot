#!/usr/bin/env node
/**
 * Remove Telegram webhook (stop receiving updates at the current URL).
 *
 * Env: BOT_TOKEN or TELEGRAM_BOT_TOKEN - required
 */
const token = (process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN || '').trim();

if (!token) {
  console.error('Error: Set BOT_TOKEN or TELEGRAM_BOT_TOKEN');
  process.exit(1);
}

const apiUrl = `https://api.telegram.org/bot${token}/deleteWebhook`;

const res = await fetch(apiUrl);
const data = await res.json().catch(() => ({}));

if (!data.ok) {
  console.error('Telegram API error:', data.description || res.statusText);
  process.exit(1);
}

console.log('Webhook deleted successfully.');
