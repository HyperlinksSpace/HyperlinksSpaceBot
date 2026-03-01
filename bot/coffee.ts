export type CoffeeTokenContext = {
  symbol: string;
  name?: string;
  description?: string;
  facts: string[];
  sourceUrls: string[];
};

type CacheRow = {
  value: CoffeeTokenContext | null;
  expiresAt: number;
};

const cache = new Map<string, CacheRow>();
const CACHE_TTL_MS = Number(process.env.COFFEE_CACHE_TTL_MS || 180000);
const MAX_CACHE_ROWS = Number(process.env.COFFEE_CACHE_MAX_ROWS || 500);

const baseUrl = (process.env.SWAP_COFFEE_BASE_URL || "https://tokens.swap.coffee").replace(/\/$/, "");
const coffeeKey = (process.env.COFFEE_KEY || "").trim();

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => (typeof item === "string" ? item.trim() : "")).filter(Boolean);
}

function normalizeSymbol(value: string): string {
  return value.replace("$", "").trim().toUpperCase();
}

function pruneCacheIfNeeded(): void {
  if (cache.size < MAX_CACHE_ROWS) return;
  let dropped = 0;
  for (const key of cache.keys()) {
    cache.delete(key);
    dropped += 1;
    if (dropped >= Math.ceil(MAX_CACHE_ROWS / 5)) break;
  }
}

function extractTokenPayload(payload: unknown): Record<string, unknown> {
  if (!isObject(payload)) return {};
  if (isObject(payload.token)) return payload.token;
  if (isObject(payload.data)) return payload.data;
  return payload;
}

export function extractTickerFromText(text: string): string | undefined {
  const fromDollar = text.match(/\$([A-Za-z0-9]{2,15})\b/);
  if (fromDollar?.[1]) return normalizeSymbol(fromDollar[1]);

  const fromUpper = text.match(/\b([A-Z0-9]{2,12})\b/);
  if (fromUpper?.[1]) return normalizeSymbol(fromUpper[1]);

  return undefined;
}

export async function fetchCoffeeContext(symbolInput: string): Promise<CoffeeTokenContext | null> {
  const symbol = normalizeSymbol(symbolInput);
  if (!symbol) return null;

  const cached = cache.get(symbol);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.value;
  }

  const headers = coffeeKey ? ({ "X-API-Key": coffeeKey } as Record<string, string>) : undefined;
  const response = await fetch(`${baseUrl}/tokens/${encodeURIComponent(symbol)}`, { headers });

  if (!response.ok) {
    cache.set(symbol, { value: null, expiresAt: Date.now() + CACHE_TTL_MS / 3 });
    return null;
  }

  const payload = (await response.json()) as unknown;
  const token = extractTokenPayload(payload);
  const payloadObj = isObject(payload) ? payload : {};

  const normalizedSymbol = normalizeSymbol(asString(token.symbol) || asString(payloadObj.symbol) || symbol);
  const name = asString(token.name) || asString(payloadObj.name);
  const description = asString(token.description) || asString(payloadObj.description) || asString(token.summary);
  const facts = [
    ...asStringArray(token.facts),
    ...asStringArray(payloadObj.facts),
    ...asStringArray(payloadObj.context),
  ];

  if (facts.length === 0) {
    if (name && description) facts.push(`${name}: ${description}`);
    else if (description) facts.push(description);
  }

  const sourceUrls = [
    asString(token.source_url),
    asString(payloadObj.source_url),
    asString(token.url),
    asString(payloadObj.url),
  ].filter((value): value is string => Boolean(value));

  const result: CoffeeTokenContext = {
    symbol: normalizedSymbol,
    name,
    description,
    facts,
    sourceUrls,
  };

  pruneCacheIfNeeded();
  cache.set(symbol, { value: result, expiresAt: Date.now() + CACHE_TTL_MS });
  return result;
}

