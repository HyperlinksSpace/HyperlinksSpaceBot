const token = (process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN || '').trim();
if (!token) throw new Error('Missing BOT_TOKEN or TELEGRAM_BOT_TOKEN');

const endpoint = `https://api.telegram.org/bot${token}/deleteWebhook`;
const response = await fetch(endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ drop_pending_updates: false }),
});
const data = await response.json();

if (!response.ok || !data.ok) {
  console.error('deleteWebhook failed', data);
  process.exit(1);
}

console.log('Webhook deleted', data.result);
