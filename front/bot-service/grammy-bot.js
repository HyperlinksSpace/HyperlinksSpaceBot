/**
 * Grammy bot instance and handler registration.
 * Used by api/bot.js after 200 ACK: bot.handleUpdate(update).
 * Keeps same behavior: /start (with AI health), /help, /ping; other text → fallback.
 */
const { Bot } = require('grammy');
const config = require('./config');
const { isAiAvailableCached } = require('./ai-health');
const { startWelcomeText, HELP_TEXT, FALLBACK_TEXT } = require('./text');
const { makeInlineKeyboardForApp } = require('./telegram');
const { logError, logWarn } = require('./logger');

if (!config.botToken) {
  throw new Error('BOT_TOKEN (or TELEGRAM_BOT_TOKEN) is required');
}

const bot = new Bot(config.botToken);

bot.command('start', async (ctx) => {
  let aiAvailable = false;
  try {
    aiAvailable = await isAiAvailableCached();
  } catch (_) {
    aiAvailable = false;
  }
  const replyMarkup = makeInlineKeyboardForApp();
  await ctx.reply(startWelcomeText(aiAvailable), {
    reply_markup: replyMarkup || undefined,
  });
});

bot.command('help', async (ctx) => {
  await ctx.reply(HELP_TEXT);
});

bot.command('ping', async (ctx) => {
  await ctx.reply('pong');
});

bot.on('message:text', async (ctx) => {
  await ctx.reply(FALLBACK_TEXT);
});

// Non-text messages (photo, sticker, etc.): reply fallback
bot.on('message', async (ctx) => {
  if (ctx.message?.text) return; // text handled by message:text
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

module.exports = { bot };
