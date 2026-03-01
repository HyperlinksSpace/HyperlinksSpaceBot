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

const BOT_TOKEN = process.env.BOT_TOKEN;
const VERCEL_URL = process.env.VERCEL_URL;

if (!BOT_TOKEN || !VERCEL_URL) {
  console.error("BOT_TOKEN and VERCEL_URL are required");
  process.exit(1);
}

const base = VERCEL_URL.startsWith("http") ? VERCEL_URL : `https://${VERCEL_URL}`;
const url = `${base.replace(/\/+$/, "")}/api/bot`;

const resp = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setWebhook`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ url }),
});

const data = await resp.json();
console.log(data);
if (!data.ok) process.exit(1);
