const token = (process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN || '').trim();
const webhookUrl = (process.env.TELEGRAM_WEBHOOK_URL || '').trim();
const secret = (process.env.TELEGRAM_WEBHOOK_SECRET || '').trim();

if (!token) throw new Error('Missing BOT_TOKEN or TELEGRAM_BOT_TOKEN');
if (!webhookUrl) throw new Error('Missing TELEGRAM_WEBHOOK_URL');

const endpoint = `https://api.telegram.org/bot${token}/setWebhook`;
const payload = { url: webhookUrl, ...(secret ? { secret_token: secret } : {}) };

const response = await fetch(endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(payload),
});
const data = await response.json();

if (!response.ok || !data.ok) {
  console.error('setWebhook failed', data);
  process.exit(1);
}

console.log('Webhook set', data.result);
