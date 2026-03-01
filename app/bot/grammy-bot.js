/**
 * Shared Grammy bot: replies "Hello" to any message.
 * Used by bot/webhook.js (Vercel) and scripts/run-bot-local.js (polling).
 */
const { Bot } = require('grammy');

function createBot(token) {
  const bot = new Bot(token);
  bot.command('start', (ctx) => ctx.reply('Hello'));
  bot.on('message:text', (ctx) => ctx.reply('Hello'));
  bot.on('message', (ctx) => ctx.reply('Hello'));
  bot.catch((err) => {
    console.error('[bot]', err);
  });
  return bot;
}

module.exports = { createBot };
