import { Configuration, RoutingApi } from "@swap-coffee/sdk";

// Aggregator / routing API (swaps, routes, etc.)
const COFFEE_BASE_URL =
  process.env.COFFEE_BASE_URL?.trim() || "https://api.swap.coffee";

// Tokens API (jettons, metadata). Default per Swap.Coffee docs.
const COFFEE_TOKENS_BASE_URL =
  process.env.COFFEE_TOKENS_BASE_URL?.trim() || "https://tokens.swap.coffee";

const COFFEE = process.env.COFFEE?.trim() || "";

export type SwapCoffeeStatus = {
  provider: "swap.coffee";
  enabled: boolean;
};

export function getSwapCoffeeStatus(): SwapCoffeeStatus {
  return {
    provider: "swap.coffee",
    enabled: Boolean(COFFEE),
  };
}

// Prepared Routing API client for future swap / routing features.
const swapCoffeeConfig =
  COFFEE &&
  new Configuration({
    basePath: COFFEE_BASE_URL,
    apiKey: (name: string) => (name === "X-Api-Key" ? COFFEE : ""),
  });

export const swapCoffeeRoutingApi = swapCoffeeConfig
  ? new RoutingApi(swapCoffeeConfig)
  : null;

export function normalizeSymbol(symbol: string | null | undefined): string {
  if (!symbol) return "";
  const cleaned = symbol.replace(/\$/g, "").replace(/\s+/g, "").trim();
  const upper = cleaned.toUpperCase();
  if (upper.length < 2 || upper.length > 10) return "";
  return upper;
}

type TokenSearchOk = {
  ok: true;
  data: any;
  elapsed_ms: number;
  source: "swap.coffee";
};

type TokenSearchError = {
  ok: false;
  error: string;
  reason?: string;
  status_code?: number;
  response_snippet?: string;
  elapsed_ms: number;
  symbol: string;
  source: "swap.coffee";
};

export type TokenSearchResult = TokenSearchOk | TokenSearchError;

export async function getTokenBySymbol(symbol: string): Promise<TokenSearchResult> {
  const normalized = normalizeSymbol(symbol);
  const started = Date.now();

  if (!normalized) {
    return {
      ok: false,
      error: "invalid_symbol",
      reason: "Symbol must be 2-10 alphanumeric characters.",
      elapsed_ms: Date.now() - started,
      symbol: symbol ?? "",
      source: "swap.coffee",
    };
  }

  // Native TON special case.
  if (normalized === "TON") {
    return {
      ok: true,
      data: {
        id: "TON",
        type: "native",
        symbol: "TON",
        name: "Toncoin",
        decimals: 9,
      },
      elapsed_ms: Date.now() - started,
      source: "swap.coffee",
    };
  }

  // Tokens API can be used with or without COFFEE key; send key only when set.
  const url = new URL(
    "/api/v3/jettons",
    COFFEE_TOKENS_BASE_URL.endsWith("/")
      ? COFFEE_TOKENS_BASE_URL
      : `${COFFEE_TOKENS_BASE_URL}/`,
  );
  url.searchParams.set("search", normalized);
  // API expects multiple verification params, not a single comma-separated value
  const verificationList = (
    process.env.TOKENS_VERIFICATION ?? "WHITELISTED,COMMUNITY,UNKNOWN"
  )
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  for (const v of verificationList.length ? verificationList : ["WHITELISTED"]) {
    url.searchParams.append("verification", v);
  }
  url.searchParams.set("size", "10");

  try {
    const headers: Record<string, string> = {};
    if (COFFEE) headers["X-Api-Key"] = COFFEE;
    const res = await fetch(url.toString(), { headers });
    const elapsed_ms = Date.now() - started;

    const text = await res.text();
    if (!res.ok) {
      return {
        ok: false,
        error: "unavailable",
        reason: "non_200",
        status_code: res.status,
        response_snippet: text.slice(0, 200),
        elapsed_ms,
        symbol: normalized,
        source: "swap.coffee",
      };
    }

    let data: unknown;
    try {
      data = JSON.parse(text);
    } catch {
      return {
        ok: false,
        error: "unavailable",
        reason: "json_parse",
        status_code: res.status,
        response_snippet: text.slice(0, 200),
        elapsed_ms,
        symbol: normalized,
        source: "swap.coffee",
      };
    }

    if (!Array.isArray(data)) {
      return {
        ok: false,
        error: "unavailable",
        reason: "unexpected_payload",
        status_code: res.status,
        response_snippet: text.slice(0, 200),
        elapsed_ms,
        symbol: normalized,
        source: "swap.coffee",
      };
    }

    if (data.length === 0) {
      return {
        ok: false,
        error: "not_found",
        elapsed_ms,
        symbol: normalized,
        source: "swap.coffee",
      };
    }

    const exact = data.find(
      (item: any) =>
        typeof item?.symbol === "string" &&
        normalizeSymbol(item.symbol) === normalized,
    );

    return {
      ok: true,
      data: exact ?? data[0],
      elapsed_ms,
      source: "swap.coffee",
    };
  } catch (err) {
    return {
      ok: false,
      error: "unavailable",
      reason: "connection",
      elapsed_ms: Date.now() - started,
      symbol: normalized,
      source: "swap.coffee",
    };
  }
}

export async function getJettonByAddress(
  address: string,
): Promise<unknown> {
  const base =
    COFFEE_TOKENS_BASE_URL.endsWith("/")
      ? COFFEE_TOKENS_BASE_URL
      : `${COFFEE_TOKENS_BASE_URL}/`;
  const url = `${base}api/v3/jettons/${encodeURIComponent(address)}`;

  const headers: Record<string, string> = {};
  if (COFFEE) headers["X-Api-Key"] = COFFEE;
  const res = await fetch(url, { headers });

  if (!res.ok) {
    throw new Error(`Swap.Coffee error: ${res.status} ${res.statusText}`);
  }

  return res.json();
}
