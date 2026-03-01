/**
 * Grammy bot instance and handler registration.
 * Used by api/bot.js after 200 ACK: bot.handleUpdate(update).
 * Portable: createBot / getBot / startPolling for webhook and local polling.
 */
const { Bot } = require('grammy');
const config = require('./config');
const { isAiAvailableCached } = require('./ai-health');
const { logError, logInfo, logWarn } = require('./logger');
const { makeInlineKeyboardForApp } = require('./telegram');
const { FALLBACK_TEXT, HELP_TEXT, startWelcomeText } = require('./text');

const DEDUPE_TTL_MS = 5 * 60 * 1000;

function nowMs() {
  return Date.now();
}

function logHandlerLatency(handler, startedAt, extra) {
  logInfo('bot_handler_latency', {
    handler,
    duration_ms: nowMs() - startedAt,
    ...(extra || {}),
  });
}

function createDedupeMiddleware() {
  const seen = new Map();

  return async (ctx, next) => {
    const updateId = ctx.update?.update_id;
    if (!Number.isInteger(updateId)) {
      return next();
    }

    const now = Date.now();
    const expiresAt = seen.get(updateId);
    if (expiresAt && expiresAt > now) {
      logWarn('telegram_update_duplicate', { update_id: updateId });
      return;
    }

    seen.set(updateId, now + DEDUPE_TTL_MS);

    // Opportunistic cleanup to keep memory bounded.
    if (seen.size > 5000) {
      for (const [id, expiry] of seen.entries()) {
        if (expiry <= now) seen.delete(id);
      }
    }

    return next();
  };
}

function createBot() {
  if (!config.botToken) {
    throw new Error('BOT_TOKEN (or TELEGRAM_BOT_TOKEN) is required');
  }

  const bot = new Bot(config.botToken);
  bot.use(createDedupeMiddleware());

  bot.command('start', async (ctx) => {
    const startedAt = nowMs();
    logInfo('bot_command', {
      command: '/start',
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });

    let aiAvailable = false;
    const aiProbeStartedAt = nowMs();
    try {
      aiAvailable = await isAiAvailableCached();
      logInfo('ai_probe_latency', {
        duration_ms: nowMs() - aiProbeStartedAt,
        ai_available: aiAvailable,
      });
    } catch (error) {
      logWarn('ai_fallback', { reason: 'probe_error' });
      logInfo('ai_probe_latency', {
        duration_ms: nowMs() - aiProbeStartedAt,
        ai_available: false,
      });
      aiAvailable = false;
    }
    const replyMarkup = makeInlineKeyboardForApp();
    await ctx.reply(startWelcomeText(aiAvailable), {
      reply_markup: replyMarkup || undefined,
    });
    logHandlerLatency('start', startedAt, {
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
  });

  bot.command('help', async (ctx) => {
    const startedAt = nowMs();
    logInfo('bot_command', {
      command: '/help',
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
    await ctx.reply(HELP_TEXT);
    logHandlerLatency('help', startedAt, {
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
  });

  bot.command('ping', async (ctx) => {
    const startedAt = nowMs();
    logInfo('bot_command', {
      command: '/ping',
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
    await ctx.reply('pong');
    logHandlerLatency('ping', startedAt, {
      update_id: ctx.update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
  });

  bot.on('message:text', async (ctx) => {
    const startedAt = nowMs();
    const update = ctx.update;
    await ctx.reply(FALLBACK_TEXT);
    logHandlerLatency('message_text', startedAt, {
      update_id: update?.update_id ?? null,
      chat_id: ctx.chat?.id ?? null,
    });
  });

  // Non-text messages (photo, sticker, etc.): reply fallback.
  bot.on('message', async (ctx) => {
    if (ctx.message?.text) return;
    logWarn('telegram_update_ignored', {
      update_id: ctx.update?.update_id ?? null,
      reason: 'no_supported_message',
    });
    await ctx.reply(FALLBACK_TEXT).catch(() => {});
  });

  bot.catch((err) => {
    logError('telegram_webhook_error', err, {
      update_id: err.ctx?.update?.update_id ?? null,
      chat_id: err.ctx?.chat?.id ?? null,
      update_kind: err.ctx?.update?.message ? 'message' : 'unknown',
    });
  });

  return bot;
}

function getBot() {
  if (!globalThis.__hyperlinksGrammyBot) {
    globalThis.__hyperlinksGrammyBot = createBot();
  }
  return globalThis.__hyperlinksGrammyBot;
}

async function startPolling() {
  const bot = getBot();
  await bot.start();
  return bot;
}

module.exports = {
  createBot,
  getBot,
  startPolling,
};
