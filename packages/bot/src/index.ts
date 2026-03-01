import { Bot, Context, NextFunction } from "grammy";

// Minimal env contract (Seva-approved)
export type BotEnv = {
  BOT_TOKEN: string;
};

type BotDeps = {
  // For future: inject AI caller, logger, etc. Keep optional for now.
  logger?: (event: Record<string, unknown>) => void;
};

let singleton: Bot<Context> | null = null;

function log(logger: BotDeps["logger"], event: Record<string, unknown>) {
  try {
    logger?.(event);
  } catch {
    // never crash bot on logging
  }
}

export function createBot(env: BotEnv, deps: BotDeps = {}): Bot<Context> {
  if (!env.BOT_TOKEN) throw new Error("BOT_TOKEN is required");

  const bot = new Bot<Context>(env.BOT_TOKEN);

  // Simple in-memory dedupe (best-effort serverless protection)
  const seen = new Set<number>();

  bot.use(async (ctx: Context, next: NextFunction) => {
    const updateId = ctx.update?.update_id;
    if (typeof updateId === "number") {
      if (seen.has(updateId)) {
        log(deps.logger, { event: "duplicate_update", update_id: updateId });
        return;
      }
      seen.add(updateId);
      // keep set bounded
      if (seen.size > 2000) {
        // naive prune
        const it = seen.values();
        for (let i = 0; i < 500; i++) {
          const v = it.next();
          if (v.done) break;
          seen.delete(v.value);
        }
      }
    }
    await next();
  });

  // Commands
  bot.command("start", async (ctx: Context) => {
    const t0 = Date.now();
    await ctx.reply(
      "Welcome 👋\n\nCommands:\n/start\n/help\n/ping\n\n(If something is down, I still respond.)"
    );
    log(deps.logger, {
      event: "bot_handler_latency",
      handler: "/start",
      duration_ms: Date.now() - t0,
    });
  });

  bot.command("help", async (ctx: Context) => {
    const t0 = Date.now();
    await ctx.reply("Help:\n/start — welcome\n/ping — health ping");
    log(deps.logger, {
      event: "bot_handler_latency",
      handler: "/help",
      duration_ms: Date.now() - t0,
    });
  });

  bot.command("ping", async (ctx: Context) => {
    const t0 = Date.now();
    await ctx.reply("pong ✅");
    log(deps.logger, {
      event: "bot_handler_latency",
      handler: "/ping",
      duration_ms: Date.now() - t0,
    });
  });

  // Fallback text handler (deterministic local reply; no Televerse)
  bot.on("message:text", async (ctx: Context) => {
    const t0 = Date.now();
    await ctx.reply("Got it ✅ Use /help for commands.");
    log(deps.logger, {
      event: "bot_handler_latency",
      handler: "message:text",
      duration_ms: Date.now() - t0,
    });
  });

  return bot;
}

export function getBot(env: BotEnv, deps: BotDeps = {}): Bot<Context> {
  if (!singleton) singleton = createBot(env, deps);
  return singleton;
}

export async function startPolling(env: BotEnv, deps: BotDeps = {}): Promise<void> {
  const bot = getBot(env, deps);
  await bot.start();
}

export * from "./ai.js";
export * from "./rag.js";
export * from "./llm.js";
export * from "./fallback.js";
export * from "./types.js";
