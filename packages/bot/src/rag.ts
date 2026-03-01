import type { RagContextResult, TokenContext } from "./types.js";

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null;
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0);
}

function normalizeSymbol(symbol: string): string {
  return symbol.replace("$", "").trim().toUpperCase();
}

export function extractTickerFromText(text: string): string | undefined {
  const fromDollar = text.match(/\$([A-Za-z0-9]{2,15})\b/);
  if (fromDollar?.[1]) return normalizeSymbol(fromDollar[1]);

  const fromUpper = text.match(/\b([A-Z0-9]{2,12})\b/);
  if (fromUpper?.[1]) return normalizeSymbol(fromUpper[1]);

  return undefined;
}

function extractTokenPayload(payload: unknown): JsonObject {
  if (!isObject(payload)) return {};
  if (isObject(payload.token)) return payload.token;
  if (isObject(payload.data)) return payload.data;
  return payload;
}

class TtlCache<V> {
  private readonly data = new Map<string, { value: V; expiresAt: number }>();

  constructor(private readonly ttlMs: number) {}

  get(key: string): V | undefined {
    const row = this.data.get(key);
    if (!row) return undefined;
    if (row.expiresAt < Date.now()) {
      this.data.delete(key);
      return undefined;
    }
    return row.value;
  }

  set(key: string, value: V): void {
    this.data.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }
}

export interface RagSource {
  getTokenContext(symbol: string): Promise<TokenContext | null>;
}

export class SwapCoffeeRagSource implements RagSource {
  private readonly baseUrl: string;
  private readonly apiKey?: string;

  constructor(options: { baseUrl?: string; apiKey?: string } = {}) {
    this.baseUrl = (options.baseUrl ?? "https://tokens.swap.coffee").replace(/\/$/, "");
    this.apiKey = options.apiKey;
  }

  async getTokenContext(rawSymbol: string): Promise<TokenContext | null> {
    const symbol = normalizeSymbol(rawSymbol);
    if (!symbol) return null;

    const headers = this.apiKey ? ({ "X-API-Key": this.apiKey } as Record<string, string>) : undefined;
    const response = await fetch(`${this.baseUrl}/tokens/${encodeURIComponent(symbol)}`, { headers });
    if (!response.ok) return null;

    const payload = await response.json();
    const tokenPayload = extractTokenPayload(payload);

    const normalizedSymbol =
      asString(tokenPayload.symbol) ??
      asString((payload as JsonObject).symbol) ??
      symbol;
    const name = asString(tokenPayload.name) ?? asString((payload as JsonObject).name);
    const description =
      asString(tokenPayload.description) ??
      asString((payload as JsonObject).description) ??
      asString(tokenPayload.summary);

    const facts = [
      ...asStringArray(tokenPayload.facts),
      ...asStringArray((payload as JsonObject).facts),
      ...asStringArray((payload as JsonObject).context),
    ];

    if (facts.length === 0) {
      if (name && description) facts.push(`${name}: ${description}`);
      else if (description) facts.push(description);
    }

    const sourceUrlCandidates = [
      asString(tokenPayload.source_url),
      asString((payload as JsonObject).source_url),
      asString(tokenPayload.url),
      asString((payload as JsonObject).url),
    ].filter((item): item is string => Boolean(item));

    return {
      symbol: normalizeSymbol(normalizedSymbol),
      name,
      description,
      facts,
      sourceUrls: sourceUrlCandidates,
      updatedAt: new Date().toISOString(),
    };
  }
}

export class RagContextBuilder {
  private readonly cache: TtlCache<TokenContext>;

  constructor(
    private readonly options: {
      source: RagSource;
      cacheTtlMs?: number;
    }
  ) {
    this.cache = new TtlCache<TokenContext>(options.cacheTtlMs ?? 120_000);
  }

  async fetchContext(input: { query: string; tokenHint?: string }): Promise<RagContextResult> {
    const requestedSymbol = normalizeSymbol(input.tokenHint ?? extractTickerFromText(input.query) ?? "");
    if (!requestedSymbol) {
      return { contextBlocks: [], sourceUrls: [], cacheHit: false };
    }

    const cached = this.cache.get(requestedSymbol);
    if (cached) {
      return {
        requestedSymbol,
        token: cached,
        contextBlocks: toContextBlocks(cached),
        sourceUrls: cached.sourceUrls,
        cacheHit: true,
      };
    }

    const token = await this.options.source.getTokenContext(requestedSymbol);
    if (!token) {
      return {
        requestedSymbol,
        contextBlocks: [],
        sourceUrls: [],
        cacheHit: false,
      };
    }

    this.cache.set(requestedSymbol, token);

    return {
      requestedSymbol,
      token,
      contextBlocks: toContextBlocks(token),
      sourceUrls: token.sourceUrls,
      cacheHit: false,
    };
  }
}

function toContextBlocks(token: TokenContext): string[] {
  return token.facts.map((fact) => `${token.symbol}: ${fact}`);
}

