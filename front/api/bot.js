/**
 * Vercel serverless: Telegram webhook gateway.
 * Uses Grammy for command and message handling (see bot-service/grammy-bot.js).
 * Contract: GET = health; POST = validate (secret, size, body) → 200 ACK → process via Grammy.
 */
const config = require('../bot-service/config');
const { bot } = require('../bot-service/grammy-bot');
const { getChatId, getUpdateKind } = require('../bot-service/telegram');
const { logError, logWarn } = require('../bot-service/logger');

function parseBodySize(req, body, fallbackBytes) {
  const header = Number(req.headers['content-length'] || 0);
  if (Number.isFinite(header) && header > 0) return header;
  try {
    return Buffer.byteLength(JSON.stringify(body || {}), 'utf8');
  } catch (_) {
    return fallbackBytes;
  }
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Telegram-Bot-Api-Secret-Token');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method === 'GET') {
    return res.status(200).json({
      ok: true,
      service: 'telegram-gateway',
      mode: 'webhook',
      framework: 'grammy',
      aiHealthConfigured: Boolean(config.aiHealthUrl),
      forwarding: 'disabled',
    });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ ok: false, error: 'method_not_allowed' });
  }

  const expectedSecret = config.webhookSecret;
  const providedSecret = (req.headers['x-telegram-bot-api-secret-token'] || '').toString();
  if (expectedSecret && providedSecret !== expectedSecret) {
    return res.status(401).json({ ok: false, error: 'unauthorized' });
  }

  const bodySize = parseBodySize(req, req.body, config.bodyLimitBytes);
  if (bodySize > config.bodyLimitBytes) {
    return res.status(413).json({ ok: false, error: 'payload_too_large' });
  }

  const update = req.body;
  if (!update || typeof update !== 'object') {
    return res.status(400).json({ ok: false, error: 'invalid_json' });
  }

  // Antifragile contract: acknowledge immediately after validation.
  res.status(200).json({ ok: true });

  const ctx = {
    update_id: update.update_id || null,
    chat_id: getChatId(update),
    update_kind: getUpdateKind(update),
  };

  setImmediate(() => {
    bot.handleUpdate(update).catch((error) => {
      logError('telegram_webhook_error', error, ctx);
    });
  });

  if (!expectedSecret) {
    logWarn('telegram_webhook_secret_not_set', { update_id: ctx.update_id });
  }
};
