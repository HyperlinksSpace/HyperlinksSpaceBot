const config = require('./config');

function getChatId(update) {
  return (
    update?.message?.chat?.id ||
    update?.edited_message?.chat?.id ||
    update?.callback_query?.message?.chat?.id ||
    update?.channel_post?.chat?.id ||
    null
  );
}

function getUserId(update) {
  return (
    update?.message?.from?.id ||
    update?.edited_message?.from?.id ||
    update?.callback_query?.from?.id ||
    update?.inline_query?.from?.id ||
    null
  );
}

function getText(update) {
  return update?.message?.text || update?.edited_message?.text || '';
}

function getMessageId(update) {
  return update?.message?.message_id || update?.edited_message?.message_id || null;
}

function getUpdateKind(update) {
  if (update?.message) return 'message';
  if (update?.edited_message) return 'edited_message';
  if (update?.callback_query) return 'callback_query';
  if (update?.inline_query) return 'inline_query';
  if (update?.channel_post) return 'channel_post';
  return 'unknown';
}

function getCommand(update) {
  const text = getText(update).trim();
  if (!text.startsWith('/')) return null;
  return text.split(/\s+/)[0].toLowerCase();
}

function makeInlineKeyboardForApp() {
  if (!config.appUrl) return undefined;
  return {
    inline_keyboard: [
      [{ text: 'Open app', web_app: { url: config.appUrl } }],
    ],
  };
}

async function sendMessage(chatId, text, options) {
  if (!config.botToken || !chatId) return;

  const endpoint = `https://api.telegram.org/bot${config.botToken}/sendMessage`;
  const payload = {
    chat_id: chatId,
    text,
    ...(options || {}),
  };

  await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

module.exports = {
  getChatId,
  getUserId,
  getText,
  getMessageId,
  getUpdateKind,
  getCommand,
  makeInlineKeyboardForApp,
  sendMessage,
};
