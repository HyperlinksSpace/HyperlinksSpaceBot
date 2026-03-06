export type ChatRole = 'system' | 'user' | 'assistant';

export type ChatMessage = {
  role: ChatRole;
  content: string;
};

export type HandleChatInput = {
  messages: ChatMessage[];
  tokenHint?: string;
};

export type HandleChatOutput = {
  text: string;
};

type CoffeeTokenContext = {
  symbol: string;
  name?: string;
  description?: string;
  facts: string[];
  sourceUrls: string[];
};

let loggedMissingOpenAiKey = false;

function lastUserText(messages: ChatMessage[]): string {
  return [...messages]
    .reverse()
    .find((message) => message.role === 'user')
    ?.content?.trim() || '';
}

function looksLikeOpenAiKey(value: string): boolean {
  return /^sk-[A-Za-z0-9\-_]+$/.test(value.trim());
}

function openAiApiKey(): string {
  const fromOpenAi = (process.env.OPENAI_API_KEY || process.env.OPENAI_KEY || '').trim();
  if (fromOpenAi) return fromOpenAi;

  const genericApiKey = (process.env.API_KEY || '').trim();
  if (looksLikeOpenAiKey(genericApiKey)) return genericApiKey;
  return '';
}

function toOpenAiMessages(messages: ChatMessage[]): Array<{ role: ChatRole; content: string }> {
  return messages
    .map((message) => ({
      role: message.role,
      content: typeof message.content === 'string' ? message.content.trim() : '',
    }))
    .filter((message) => message.content.length > 0);
}

function normalizeSymbol(value: string): string {
  return value.replace('$', '').trim().toUpperCase();
}

function extractTickerFromText(text: string): string | undefined {
  const fromDollar = text.match(/\$([A-Za-z0-9]{2,15})\b/);
  if (fromDollar?.[1]) return normalizeSymbol(fromDollar[1]);

  const fromUpper = text.match(/\b([A-Z0-9]{2,12})\b/);
  if (fromUpper?.[1]) return normalizeSymbol(fromUpper[1]);

  return undefined;
}

function extractTickerFromMessages(messages: ChatMessage[]): string | undefined {
  for (const message of [...messages].reverse()) {
    if (typeof message.content !== 'string') continue;
    const symbol = extractTickerFromText(message.content);
    if (symbol) return symbol;
  }
  return undefined;
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === 'string' ? item.trim() : ''))
    .filter(Boolean);
}

function asObject(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function extractTokenPayload(payloadObj: Record<string, unknown>): Record<string, unknown> {
  if (typeof payloadObj.token === 'object' && payloadObj.token !== null) {
    return payloadObj.token as Record<string, unknown>;
  }
  if (typeof payloadObj.data === 'object' && payloadObj.data !== null) {
    return payloadObj.data as Record<string, unknown>;
  }
  return payloadObj;
}

async function fetchCoffeeContext(symbolInput: string): Promise<CoffeeTokenContext | null> {
  const symbol = normalizeSymbol(symbolInput);
  if (!symbol) return null;

  const baseUrl = (process.env.SWAP_COFFEE_BASE_URL || 'https://tokens.swap.coffee').replace(/\/$/, '');
  const coffeeKey = (process.env.COFFEE_KEY || '').trim();
  const timeoutMs = Number(process.env.COFFEE_TIMEOUT_MS || 6000);
  const headers = coffeeKey ? ({ 'X-API-Key': coffeeKey } as Record<string, string>) : undefined;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${baseUrl}/tokens/${encodeURIComponent(symbol)}`, {
      headers,
      signal: controller.signal,
    });
    if (!response.ok) return null;

    const payload = (await response.json()) as unknown;
    const payloadObj = asObject(payload);
    const token = extractTokenPayload(payloadObj);

    const normalizedSymbol = normalizeSymbol(
      asString(token.symbol) || asString(payloadObj.symbol) || symbol,
    );
    const name = asString(token.name) || asString(payloadObj.name);
    const description =
      asString(token.description) ||
      asString(payloadObj.description) ||
      asString(token.summary);
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

    return {
      symbol: normalizedSymbol,
      name,
      description,
      facts,
      sourceUrls,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function withContextMessages(
  messages: ChatMessage[],
  facts: string[],
  sourceUrls: string[],
): ChatMessage[] {
  if (facts.length === 0) return messages;

  const contextLines = [
    'Use this verified token context if relevant to the user question.',
    ...facts,
  ];
  if (sourceUrls.length > 0) contextLines.push(`Sources: ${sourceUrls.join(', ')}`);

  return [{ role: 'system', content: contextLines.join('\n') }, ...messages];
}

function buildTokenFallback(
  symbol: string,
  name?: string,
  description?: string,
): string {
  const normalized = symbol.replace('$', '').toUpperCase();
  const title = name?.trim() || `$${normalized}`;
  if (description?.trim()) {
    return `${title} (${normalized}) currently reads like a narrative-driven token.\n\n${description.trim()}\n\nIf useful, I can break this down into thesis, risk flags, and what to verify before entering.`;
  }
  return `${title} (${normalized}) looks like a speculative token where narrative and risk management matter most.\n\nI can provide a compact brief with thesis, catalysts, and risk checks.`;
}

async function completeWithOpenAi(messages: ChatMessage[]): Promise<string | null> {
  const apiKey = openAiApiKey();
  if (!apiKey) {
    if (!loggedMissingOpenAiKey) {
      console.error(
        '[bot/handler] missing OPENAI_API_KEY/OPENAI_KEY (or API_KEY with OpenAI format).',
      );
      loggedMissingOpenAiKey = true;
    }
    return null;
  }

  const baseUrl = (process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
  const model = (process.env.OPENAI_MODEL || 'gpt-4o-mini').trim();
  const timeoutMs = Number(process.env.OPENAI_TIMEOUT_MS || 20000);
  const payloadMessages = toOpenAiMessages(messages);
  if (payloadMessages.length === 0) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: payloadMessages,
        temperature: 0.3,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = (await res.text().catch(() => '')).slice(0, 320);
      throw new Error(`openai_http_${res.status}${body ? `: ${body}` : ''}`);
    }

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const content = data.choices?.[0]?.message?.content?.trim();
    return content || null;
  } finally {
    clearTimeout(timeout);
  }
}

export async function handleChat(input: HandleChatInput): Promise<HandleChatOutput> {
  const userText = lastUserText(input.messages);
  if (!userText) {
    return { text: 'I could not read that message.' };
  }

  let openAiError: string | undefined;

  const ticker =
    normalizeSymbol(input.tokenHint || '') ||
    extractTickerFromText(userText) ||
    extractTickerFromMessages(input.messages);

  let coffee: CoffeeTokenContext | null = null;
  if (ticker) {
    coffee = await fetchCoffeeContext(ticker);
  }

  try {
    const messages = withContextMessages(
      input.messages,
      coffee?.facts || [],
      coffee?.sourceUrls || [],
    );
    const aiText = await completeWithOpenAi(messages);
    if (aiText && aiText.length > 0) {
      return { text: aiText };
    }
  } catch (err) {
    openAiError = err instanceof Error ? err.message : 'unknown_openai_error';
    console.error('[bot/handler] openai failed', err);
  }

  if (ticker) {
    return {
      text: buildTokenFallback(
        ticker,
        coffee?.name,
        coffee?.description,
      ),
    };
  }

  if (openAiError?.includes('openai_http_429')) {
    return {
      text: 'AI quota is exhausted right now. Please add credits/billing for the AI key. Meanwhile, include a token symbol (example: DOGS) and I can send a fallback brief.',
    };
  }

  if (!openAiApiKey()) {
    return {
      text: 'AI key is not configured in runtime. Set OPENAI_API_KEY in Vercel environment variables.',
    };
  }

  return {
    text: 'I am online, but AI is temporarily unavailable. Please try again in a moment.',
  };
}

export default handleChat;
