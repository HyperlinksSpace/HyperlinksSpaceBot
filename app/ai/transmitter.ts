import type { AiMode, AiRequestBase, AiResponseBase } from "./openai.js";
import { callOpenAiChat } from "./openai.js";
import {
  getTokenBySymbol,
  normalizeSymbol,
  type TokenSearchResult,
} from "../blockchain/coffee.js";

export type AiRequest = AiRequestBase & {
  mode?: AiMode;
};

export type AiResponse = AiResponseBase;

function extractSymbolCandidate(input: string): string | null {
  const raw = input.trim();
  if (!raw) return null;

  // Simple patterns like "USDT", "$USDT", "USDT on TON".
  const parts = raw.split(/\s+/);
  const first = parts[0]?.replace(/^\$/g, "") ?? "";
  const normalized = normalizeSymbol(first);
  return normalized || null;
}

function buildTokenFactsBlock(symbol: string, token: any): string {
  const lines: string[] = [];

  const sym = token?.symbol ?? symbol;
  const name = token?.name ?? null;
  const address = token?.id ?? token?.address ?? null;
  const type = token?.type ?? "token";
  const decimals = token?.decimals ?? token?.metadata?.decimals ?? null;
  const verification =
    token?.verification ?? token?.metadata?.verification ?? null;

  const market = token?.market_stats ?? {};
  const holders =
    market?.holders_count ?? token?.holders ?? market?.holders ?? null;
  const priceUsd = market?.price_usd ?? null;
  const mcap = market?.mcap ?? market?.fdmc ?? null;
  const volume24h = market?.volume_usd_24h ?? null;

  lines.push(`Symbol: ${sym}`);
  if (name) {
    lines.push(`Name: ${name}`);
  }
  lines.push(`Type: ${type}`);
  lines.push(`Blockchain: TON`);
  if (address) {
    lines.push(`Address: ${address}`);
  }
  if (decimals != null) {
    lines.push(`Decimals: ${decimals}`);
  }
  if (verification) {
    lines.push(`Verification: ${verification}`);
  }
  if (holders != null) {
    lines.push(`Holders: ${holders}`);
  }
  if (priceUsd != null) {
    lines.push(`Price (USD): ${priceUsd}`);
  }
  if (mcap != null) {
    lines.push(`Market cap (USD): ${mcap}`);
  }
  if (volume24h != null) {
    lines.push(`24h volume (USD): ${volume24h}`);
  }

  return lines.join("\n");
}

async function handleTokenInfo(
  request: AiRequest,
): Promise<AiResponse> {
  const trimmed = request.input?.trim() ?? "";
  const symbolCandidate = extractSymbolCandidate(trimmed);

  if (!symbolCandidate) {
    return {
      ok: false,
      provider: "openai",
      mode: "token_info",
      error: "Could not detect a token symbol. Try sending something like USDT.",
    };
  }

  const tokenResult: TokenSearchResult = await getTokenBySymbol(
    symbolCandidate,
  );

  if (!tokenResult.ok) {
    return {
      ok: false,
      provider: "openai",
      mode: "token_info",
      error:
        tokenResult.error === "not_found"
          ? `Token ${symbolCandidate} was not found on TON.`
          : "Token service is temporarily unavailable.",
      meta: {
        symbol: symbolCandidate,
        reason: tokenResult.reason,
        status_code: tokenResult.status_code,
      },
    };
  }

  const token = tokenResult.data;
  const facts = buildTokenFactsBlock(symbolCandidate, token);

  const promptParts = [
    "You are a concise TON token analyst.",
    "",
    "Facts about the token:",
    facts,
    "",
    "User question or context:",
    trimmed,
  ];

  const composedInput = promptParts.join("\n");

  const result = await callOpenAiChat("token_info", {
    input: composedInput,
    userId: request.userId,
    context: {
      ...request.context,
      symbol: symbolCandidate,
      token,
      source: "swap.coffee",
    },
  });

  return {
    ...result,
    mode: "token_info",
    meta: {
      ...(result.meta ?? {}),
      symbol: symbolCandidate,
      token,
    },
  };
}

export async function transmit(request: AiRequest): Promise<AiResponse> {
  const mode: AiMode = request.mode ?? "chat";

  if (mode === "token_info") {
    return handleTokenInfo(request);
  }

  return callOpenAiChat(mode, {
    input: request.input,
    userId: request.userId,
    context: request.context,
  });
}
