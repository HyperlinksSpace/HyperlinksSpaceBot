export type ChatRole = "system" | "user" | "assistant";

export type OutputLanguage = "en" | "ru";

export type ChatMessage = {
  role: ChatRole;
  content: string;
};

export type TokenContext = {
  symbol: string;
  name?: string;
  description?: string;
  facts: string[];
  sourceUrls: string[];
  updatedAt: string;
};

export type LlmChatRequest = {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
};

export type LlmStreamChunk = {
  token?: string;
  error?: string;
  done?: boolean;
};

export type GenerateAnswerInput = {
  messages: ChatMessage[];
  model?: string;
  temperature?: number;
  tokenHint?: string;
};

export type GenerateAnswerMeta = {
  language: OutputLanguage;
  tickerSymbol?: string;
  usedFallback: boolean;
  cacheHit: boolean;
  sourceUrls: string[];
};

export type GenerateAnswerResult = {
  text: string;
  meta: GenerateAnswerMeta;
};

export type RagContextResult = {
  requestedSymbol?: string;
  token?: TokenContext;
  contextBlocks: string[];
  sourceUrls: string[];
  cacheHit: boolean;
};

