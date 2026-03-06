/**
 * Shared Grammy bot.
 * Used by bot/webhook.ts (Vercel) and scripts/run-bot-local.ts (polling).
 */
import { Bot, type Context } from 'grammy';
import { normalizeUsername, upsertUserFromBot } from '../server/users.js';
import { handleChat, type ChatMessage } from './handler.js';

const chatHistory = new Map<string, ChatMessage[]>();
const MAX_HISTORY_MESSAGES = 8;
const MAX_CHAT_ROWS = 500;

function getChatKey(ctx: Context): string | null {
  const id = ctx.chat?.id ?? ctx.from?.id;
  if (typeof id === 'number' || typeof id === 'bigint') return String(id);
  return null;
}

function pruneHistoryIfNeeded(): void {
  if (chatHistory.size < MAX_CHAT_ROWS) return;
  let dropped = 0;
  for (const key of chatHistory.keys()) {
    chatHistory.delete(key);
    dropped += 1;
    if (dropped >= Math.ceil(MAX_CHAT_ROWS / 5)) break;
  }
}

function getHistory(chatKey: string | null): ChatMessage[] {
  if (!chatKey) return [];
  return chatHistory.get(chatKey) || [];
}

function setHistory(chatKey: string | null, history: ChatMessage[]): void {
  if (!chatKey) return;
  pruneHistoryIfNeeded();
  chatHistory.set(chatKey, history.slice(-MAX_HISTORY_MESSAGES));
}

export function createBot(token: string): Bot {
  const bot = new Bot(token);

  async function handleUserUpsert(ctx: Context): Promise<void> {
    try {
      const from = ctx.from;
      if (!from) return;

      const telegramUsername = normalizeUsername(from.username);
      if (!telegramUsername) return;

      const locale =
        typeof from.language_code === 'string' ? from.language_code : null;

      await upsertUserFromBot({ telegramUsername, locale });
    } catch (err) {
      console.error('[bot] upsert user failed', err);
    }
  }

  bot.command('start', async (ctx: Context) => {
    await handleUserUpsert(ctx);
    setHistory(getChatKey(ctx), []);
    await ctx.reply('Hi. I am ready. Send any text and I will answer.');
  });

  bot.on('message:text', async (ctx: Context) => {
    await handleUserUpsert(ctx);

    const text = ctx.message?.text;
    if (!text) {
      await ctx.reply('I could not read that message.');
      return;
    }

    const chatKey = getChatKey(ctx);
    const messages: ChatMessage[] = [
      ...getHistory(chatKey),
      { role: 'user', content: text },
    ];

    try {
      const result = await handleChat({
        messages,
      });
      await ctx.reply(result.text);
      setHistory(chatKey, [...messages, { role: 'assistant', content: result.text }]);
    } catch (err) {
      console.error('[bot] handleChat failed', err);
      await ctx.reply('AI is temporarily unavailable. Please try again in a moment.');
    }
  });

  bot.catch((err) => {
    console.error('[bot]', err);
  });

  return bot;
}
