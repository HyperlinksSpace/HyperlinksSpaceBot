import type { Context } from "grammy";
import { normalizeSymbol } from "../blockchain/coffee.js";
import { transmit, transmitStream } from "../ai/transmitter.js";
import { normalizeUsername } from "../database/users.js";
import { getMaxTelegramUpdateIdForThread } from "../database/messages.js";
import { mdToTelegramHtml } from "./format.js";

const DRAFT_ID = 1;
const MAX_DRAFT_TEXT_LENGTH = 4096;
/** Throttle draft updates to avoid Telegram 429 rate limits. */
const DRAFT_THROTTLE_MS = 500;
/** If content grew by more than this many chars, send immediately so long tail doesn't stick. */
const DRAFT_MIN_CHARS_TO_SEND_NOW = 200;

/** Track latest generation per chat so newer messages cancel older streams. */
const chatGenerations = new Map<number, number>();

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
  /** When the user writes in a topic/thread, we must send drafts and replies to the same thread. */
  const messageThreadId =
    typeof (ctx.message as { message_thread_id?: number } | undefined)?.message_thread_id === "number"
      ? (ctx.message as { message_thread_id: number }).message_thread_id
      : undefined;
  const replyOptions = messageThreadId !== undefined ? { message_thread_id: messageThreadId } : undefined;
  const replyOptionsWithHtml = { ...replyOptions, parse_mode: "HTML" as const };

  if (!text) {
    const msg = ctx.message;
    const hasTextOrCaption =
      (msg && "text" in msg) || (msg && "caption" in (msg as any));
    if (hasTextOrCaption) {
      await ctx.reply("Send me a message or token ticker (e.g. USDT).", replyOptions);
    }
    return;
  }

  const user_telegram = normalizeUsername(from?.username);
  const thread_id = messageThreadId ?? 0;
  const update_id = typeof (ctx.update as { update_id?: number }).update_id === "number"
    ? (ctx.update as { update_id: number }).update_id
    : undefined;
  const threadContext =
    user_telegram && update_id !== undefined
      ? { user_telegram, thread_id, type: "bot" as const, telegram_update_id: update_id }
      : undefined;

  const mode = looksLikeTicker(text) ? "token_info" : "chat";
  const chatId = ctx.chat?.id;
  const isPrivate = ctx.chat?.type === "private";
  const canStream = isPrivate && typeof chatId === "number";

  const numericChatId =
    typeof chatId === "number" ? chatId : undefined;
  let generation = 0;
  if (numericChatId !== undefined) {
    const prev = chatGenerations.get(numericChatId) ?? 0;
    generation = prev + 1;
    chatGenerations.set(numericChatId, generation);
  }
  const isCancelled = (): boolean =>
    numericChatId !== undefined &&
    chatGenerations.get(numericChatId) !== generation;

  const shouldAbortSend = async (): Promise<boolean> => {
    if (!threadContext) return false;
    const max = await getMaxTelegramUpdateIdForThread(
      threadContext.user_telegram,
      threadContext.thread_id,
      "bot",
    );
    return max !== null && max !== threadContext.telegram_update_id;
  };

  let result: Awaited<ReturnType<typeof transmit>>;

  if (canStream && chatId !== undefined) {
    let lastDraft = "";
    let lastSendTime = 0;
    let pending: string | null = null;
    let throttleTimer: ReturnType<typeof setTimeout> | null = null;
    let draftsDisabled = false;

    const sendDraftOnce = async (slice: string): Promise<void> => {
      if (await shouldAbortSend()) return;
      if (isCancelled() || draftsDisabled) return;
      const formattedSlice = mdToTelegramHtml(slice);
      const sendDraft = (text: string, opts: Record<string, unknown>) =>
        ctx.api.sendMessageDraft(chatId, DRAFT_ID, text, opts as Parameters<typeof ctx.api.sendMessageDraft>[3]);
      try {
        await sendDraft(formattedSlice, replyOptionsWithHtml);
      } catch (e: unknown) {
        const err = e as { error_code?: number; parameters?: { retry_after?: number } };
        const is429 = err?.error_code === 429;
        if (is429) {
          const waitMs = (err.parameters?.retry_after ?? 1) * 1000;
          await new Promise((r) => setTimeout(r, Math.min(waitMs, 2000)));
          try {
            await sendDraft(formattedSlice, replyOptionsWithHtml);
          } catch (e2) {
            console.error("[bot][draft]", e2);
            draftsDisabled = true;
          }
        } else {
          try {
            await sendDraft(slice, replyOptions ?? {});
          } catch (_) {
            console.error("[bot][draft]", e);
          }
        }
      }
    };

    const flushDraft = async (): Promise<void> => {
      if (isCancelled()) return;
      if (pending === null) return;
      const slice = pending;
      pending = null;
      throttleTimer = null;
      lastDraft = slice;
      lastSendTime = Date.now();
      await sendDraftOnce(slice);
    };

    const sendDraft = async (accumulated: string): Promise<void> => {
      if (isCancelled()) return;
      const slice = accumulated.length > MAX_DRAFT_TEXT_LENGTH
        ? accumulated.slice(0, MAX_DRAFT_TEXT_LENGTH)
        : accumulated;
      if (slice === lastDraft) return;
      if (!slice.trim()) return;
      const now = Date.now();
      const throttleElapsed = now - lastSendTime;
      const bigChunk = slice.length - lastDraft.length >= DRAFT_MIN_CHARS_TO_SEND_NOW;
      const shouldSendNow =
        throttleElapsed >= DRAFT_THROTTLE_MS || (bigChunk && slice.length > lastDraft.length);
      if (shouldSendNow) {
        lastDraft = slice;
        lastSendTime = now;
        pending = null;
        if (throttleTimer) {
          clearTimeout(throttleTimer);
          throttleTimer = null;
        }
        await sendDraftOnce(slice);
      } else {
        pending = slice;
        if (!throttleTimer) {
          throttleTimer = setTimeout(
            () => void flushDraft(),
            DRAFT_THROTTLE_MS - throttleElapsed,
          );
        }
      }
    };

    result = await transmitStream(
      { input: text, userId, context, mode, threadContext },
      sendDraft,
      { isCancelled },
    );
    if (result.skipped) return;
    if (isCancelled()) {
      return;
    }
    if (throttleTimer) {
      clearTimeout(throttleTimer);
      throttleTimer = null;
    }
    await flushDraft();

    if (
      mode === "token_info" &&
      (!result.ok || !result.output_text) &&
      result.error?.includes("temporarily unavailable")
    ) {
      if (isCancelled()) {
        return;
      }
      lastDraft = "";
      result = await transmitStream(
        {
          input: text,
          userId,
          context,
          mode: "chat",
          threadContext: threadContext ? { ...threadContext, skipClaim: true } : undefined,
        },
        sendDraft,
        { isCancelled },
      );
      if (result.skipped) return;
      if (isCancelled()) {
        return;
      }
      if (throttleTimer) {
        clearTimeout(throttleTimer);
        throttleTimer = null;
      }
      await flushDraft();
    }
  } else {
    result = await transmit({ input: text, userId, context, mode, threadContext });
    if (result.skipped) return;
    if (isCancelled()) {
      return;
    }

    if (
      mode === "token_info" &&
      (!result.ok || !result.output_text) &&
      result.error?.includes("temporarily unavailable")
    ) {
      if (isCancelled()) {
        return;
      }
      result = await transmit({
        input: text,
        userId,
        context,
        mode: "chat",
        threadContext: threadContext ? { ...threadContext, skipClaim: true } : undefined,
      });
      if (result.skipped) return;
    }
  }

  if (!result.ok || !result.output_text) {
    if (await shouldAbortSend()) return;
    if (isCancelled()) {
      return;
    }
    const errMsg = result.error ?? "AI returned no output.";
    console.error("[bot][ai]", errMsg);
    const message: string =
      mode === "token_info" && result.error
        ? result.error
        : "AI is temporarily unavailable. Please try again in a moment.";
    await ctx.reply(message, replyOptions);
    return;
  }

  if (await shouldAbortSend()) return;
  if (isCancelled()) {
    return;
  }
  const formatted = mdToTelegramHtml(result.output_text);
  try {
    await ctx.reply(formatted, replyOptionsWithHtml);
  } catch (e) {
    // If Telegram rejects (e.g. invalid HTML), send as plain text
    await ctx.reply(result.output_text, replyOptions);
  }
}
