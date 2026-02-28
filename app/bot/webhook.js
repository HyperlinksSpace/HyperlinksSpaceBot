/**
 * Telegram webhook handler.
 * GET: set webhook to VERCEL_URL + /api/bot (requires BOT_TOKEN; VERCEL_URL is set by Vercel).
 * POST: handle update (reply "Hello"), requires BOT_TOKEN.
 * Supports Vercel Web API (Request → Response) and legacy (req, res).
 */
const { createBot } = require('./grammy-bot');

const BOT_TOKEN = process.env.BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN;
const BASE_URL = (process.env.SELF_URL || '').replace(/\/$/, '') || (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : '');

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

async function setWebhook() {
  if (!BOT_TOKEN || !BASE_URL) return null;
  const url = `${BASE_URL}/api/bot`;
  const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/setWebhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
  });
  const data = await res.json();
  return data;
}

async function handleRequest(request) {
  const method = request.method;
  console.log('[webhook]', method, new Date().toISOString());

  if (method === 'OPTIONS') return jsonResponse({}, 200);

  if (method === 'GET') {
    if (BASE_URL && BOT_TOKEN) {
      const result = await setWebhook();
      return jsonResponse({
        ok: true,
        webhook_set: result?.ok === true,
        url: `${BASE_URL}/api/bot`,
      });
    }
    return jsonResponse({
      ok: true,
      service: 'telegram-bot',
      bot: !!BOT_TOKEN,
      vercel_url_set: !!BASE_URL,
    });
  }

  if (method !== 'POST') return jsonResponse({ ok: false, error: 'method_not_allowed' }, 405);
  if (!BOT_TOKEN) return jsonResponse({ ok: false, error: 'BOT_TOKEN not set' }, 500);

  let update;
  try {
    update = typeof request.json === 'function' ? await request.json() : request.body;
  } catch (e) {
    return jsonResponse({ ok: false, error: 'invalid_body' }, 400);
  }
  if (typeof update === 'string') {
    try {
      update = JSON.parse(update);
    } catch (e) {
      return jsonResponse({ ok: false, error: 'invalid_body' }, 400);
    }
  }
  if (!update || typeof update !== 'object') return jsonResponse({ ok: false, error: 'invalid_body' }, 400);

  const updateId = update.update_id;
  console.log('[webhook] POST update', updateId);
  const bot = createBot(BOT_TOKEN);
  try {
    await bot.init();
    await bot.handleUpdate(update);
    console.log('[webhook] handled update', updateId);
  } catch (err) {
    console.error('[bot]', err);
    return jsonResponse({ ok: false, error: 'handler_error' }, 500);
  }
  return jsonResponse({ ok: true });
}

// Legacy default handler (req, res) e.g. local; also exposes handleRequest for api/bot.js named GET/POST
async function handler(request, context) {
  if (request && typeof request.json === 'function') {
    return handleRequest(request);
  }
  const req = request;
  const res = context;
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method === 'GET') {
    if (BASE_URL && BOT_TOKEN) {
      const result = await setWebhook();
      return res.status(200).json({ ok: true, webhook_set: result?.ok === true, url: `${BASE_URL}/api/bot` });
    }
    return res.status(200).json({ ok: true, service: 'telegram-bot', bot: !!BOT_TOKEN, vercel_url_set: !!BASE_URL });
  }
  if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  if (!BOT_TOKEN) return res.status(500).json({ ok: false, error: 'BOT_TOKEN not set' });
  let update = req.body;
  if (typeof update === 'string') {
    try { update = JSON.parse(update); } catch (e) { return res.status(400).json({ ok: false, error: 'invalid_body' }); }
  }
  if (!update || typeof update !== 'object') return res.status(400).json({ ok: false, error: 'invalid_body' });
  const bot = createBot(BOT_TOKEN);
  try {
    await bot.init();
    await bot.handleUpdate(update);
  } catch (err) {
    console.error('[bot]', err);
    return res.status(500).json({ ok: false, error: 'handler_error' });
  }
  return res.status(200).json({ ok: true });
}
module.exports = handler;
module.exports.handleRequest = handleRequest;
