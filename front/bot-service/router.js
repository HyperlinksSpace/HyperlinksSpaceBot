/**
 * Legacy router path retained for compatibility reference.
 * Active runtime uses grammy-bot.js directly; Televerse forwarding is paused.
 */
const { isAiAvailableCached } = require('./ai-health');
const { HELP_TEXT, FALLBACK_TEXT, startWelcomeText } = require('./text');
const {
  getChatId,
  getCommand,
  getMessageId,
  getText,
  makeInlineKeyboardForApp,
  sendMessage,
} = require('./telegram');
const { forwardToTeleverse } = require('./downstream');
const { logWarn, logError } = require('./logger');

async function handleCommand(update, command) {
  const chatId = getChatId(update);
  if (!chatId) return { handled: false };

  if (command === '/start') {
    let aiAvailable = false;
    try {
      aiAvailable = await isAiAvailableCached();
    } catch (_) {
      aiAvailable = false;
    }

    const replyMarkup = makeInlineKeyboardForApp();
    await sendMessage(chatId, startWelcomeText(aiAvailable), replyMarkup ? { reply_markup: replyMarkup } : undefined);
    return { handled: true };
  }

  if (command === '/help') {
    await sendMessage(chatId, HELP_TEXT);
    return { handled: true };
  }

  if (command === '/ping') {
    await sendMessage(chatId, 'pong');
    return { handled: true };
  }

  return { handled: false };
}

async function processUpdate(update) {
  const command = getCommand(update);

  if (command) {
    const result = await handleCommand(update, command);
    if (result.handled) return;
  }

  const text = getText(update);
  if (text) {
    try {
      const forwarded = await forwardToTeleverse(update);
      if (!forwarded.forwarded) {
        await sendMessage(getChatId(update), FALLBACK_TEXT);
      }
      return;
    } catch (error) {
      logError('televerse_forward_error', error, {
        update_id: update?.update_id || null,
        chat_id: getChatId(update),
        message_id: getMessageId(update),
      });
      await sendMessage(getChatId(update), FALLBACK_TEXT);
      return;
    }
  }

  logWarn('telegram_update_ignored', {
    update_id: update?.update_id || null,
    reason: 'no_supported_message',
  });
}

module.exports = {
  processUpdate,
};
