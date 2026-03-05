import type { Context } from "grammy";
import { normalizeSymbol } from "../blockchain/coffee.js";
import { transmit } from "../ai/transmitter.js";

type BotSourceContext = {
  source: "bot";
  username?: string | null;
  locale?: string | null;
};

function buildBotContext(ctx: Context): BotSourceContext {
  const from = ctx.from;
  return {
    source: "bot",
    username: from?.username ?? null,
    locale:
      typeof from?.language_code === "string" ? from.language_code : null,
  };
}

function extractPlainText(ctx: Context): string | null {
  const msg = ctx.message;
  if (!msg) return null;
  if ("text" in msg && typeof msg.text === "string") {
    return msg.text.trim();
  }
  if ("caption" in msg && typeof (msg as any).caption === "string") {
    return (msg as any).caption.trim();
  }
  return null;
}

/** True if message looks like a single token ticker (e.g. DOGS, TON, $USDT). */
function looksLikeTicker(text: string): boolean {
  const parts = text.split(/\s+/);
  const first = parts[0]?.replace(/^\$/g, "") ?? "";
  return parts.length === 1 && normalizeSymbol(first).length > 0;
}

export async function handleBotAiResponse(ctx: Context): Promise<void> {
  const from = ctx.from;
  const userId = from ? String(from.id) : undefined;
  const context = buildBotContext(ctx);

  const text = extractPlainText(ctx);
  if (!text) {
    await ctx.reply("Send me a message or token ticker (e.g. USDT).");
    return;
  }

  const mode = looksLikeTicker(text) ? "token_info" : "chat";
  let result = await transmit({
    input: text,
    userId,
    context,
    mode,
  });

  // COFFEE is optional: if token service is unavailable, answer as normal chat
  if (
    mode === "token_info" &&
    (!result.ok || !result.output_text) &&
    result.error?.includes("temporarily unavailable")
  ) {
    result = await transmit({
      input: text,
      userId,
      context,
      mode: "chat",
    });
  }

  if (!result.ok || !result.output_text) {
    console.error("[bot][ai]", result.error);
    const isTokenMode = mode === "token_info" && result.error;
    const message = isTokenMode
      ? result.error
      : "AI is temporarily unavailable. Please try again in a moment.";
    await ctx.reply(message);
    return;
  }

  await ctx.reply(result.output_text);
}
