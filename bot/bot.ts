import { Bot, type Context } from "grammy";
import { handleChat } from "./handler.js";

function mustEnv(name: string): string {
  const value = (process.env[name] || "").trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

export function createBot(): Bot<Context> {
  const token = mustEnv("BOT_TOKEN");
  const bot = new Bot<Context>(token);

  bot.command("start", async (ctx) => {
    await ctx.reply("Welcome. Send a token question like $TON.");
  });

  bot.command("help", async (ctx) => {
    await ctx.reply("Ask about a token (e.g. $DOGS, $TON).");
  });

  bot.on("message:text", async (ctx) => {
    const userText = ctx.message.text || "";
    const output = await handleChat({
      messages: [{ role: "user", content: userText }],
    });
    await ctx.reply(output.text);
  });

  bot.catch((error) => {
    console.error("[bot:error]", error.error?.message || "unknown");
  });

  return bot;
}

export async function startPolling(): Promise<void> {
  const bot = createBot();
  await bot.start();
}

