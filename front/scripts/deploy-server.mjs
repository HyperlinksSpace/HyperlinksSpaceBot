const token = (process.env.BOT_TOKEN || '').trim();
const vercelUrlRaw = (process.env.VERCEL_URL || '').trim();

if (!token) {
  console.error('Missing BOT_TOKEN');
  process.exit(1);
}

if (!vercelUrlRaw) {
  console.error('Missing VERCEL_URL');
  process.exit(1);
}

const baseUrl = /^https?:\/\//i.test(vercelUrlRaw)
  ? vercelUrlRaw.replace(/\/$/, '')
  : `https://${vercelUrlRaw.replace(/\/$/, '')}`;
const webhookUrl = `${baseUrl}/api/bot`;

const endpoint = `https://api.telegram.org/bot${token}/setWebhook`;
const response = await fetch(endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ url: webhookUrl }),
});

const data = await response.json();
if (!response.ok || !data.ok) {
  console.error('[bot:deploy] setWebhook failed', data);
  process.exit(1);
}

console.log('[bot:deploy] Webhook set successfully');
console.log('[bot:deploy] URL:', webhookUrl);
