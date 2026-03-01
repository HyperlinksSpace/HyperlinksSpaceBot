import type { ChatMessage, OutputLanguage } from "./types.js";

type TokenFallbackInput = {
  symbol: string;
  name?: string;
  description?: string;
  language: OutputLanguage;
};

const PLAIN_FALLBACK_PHRASES_EN = [
  "i don't have verified data",
  "token provider unavailable",
  "i cannot verify",
  "no verified data",
];

const PLAIN_FALLBACK_PHRASES_RU = [
  "u menia net proverennykh dannykh",
  "u menya net proverennykh dannykh",
  "ne mogu proverit",
  "net proverennykh dannykh",
];

function normalize(text: string): string {
  return text.toLowerCase().replace(/\s+/g, " ").trim();
}

export function hasGenericFallbackText(text: string, language: OutputLanguage): boolean {
  const value = normalize(text);
  const list = language === "ru" ? PLAIN_FALLBACK_PHRASES_RU : PLAIN_FALLBACK_PHRASES_EN;
  return list.some((phrase) => value.includes(phrase));
}

export function fallbackNarrative(input: TokenFallbackInput): string {
  const symbol = input.symbol.replace("$", "").toUpperCase();
  const title = input.name?.trim() || `$${symbol}`;
  const description = input.description?.trim();

  if (input.language === "ru") {
    if (description) {
      return `${title} (${symbol}) seichas vyglyadit kak proekt s sobstvennym komiuniti i narrativom.\n\n${description}\n\nEsli nuzhno, mogu razobrat eto kak kratkii tezis: ideia, utiliti, riski i chto proveriat pered vhodom.`;
    }
    return `${title} (${symbol}) vyglyadit kak rannii/spekuliativnyi aktiv, gde kontekst i risk vazhnee shuma.\n\nMogu dat struktuirovannyi razbor: chto eto za aktiv, kakie u nego draivery, i kakie proverki sdelat pered sdelkoi.`;
  }

  if (description) {
    return `${title} (${symbol}) currently reads like a narrative-driven token with active community attention.\n\n${description}\n\nIf useful, I can break this down into a short checklist: thesis, utility signals, risk flags, and what to verify before entering.`;
  }
  return `${title} (${symbol}) looks like an early-stage/speculative token where narrative and risk management matter more than noise.\n\nI can provide a compact brief with thesis, catalysts, risks, and a verification checklist before taking a position.`;
}

export function detectRequestedLanguage(messages: ChatMessage[], fallback: OutputLanguage = "en"): OutputLanguage {
  for (const message of messages) {
    if (message.role !== "system") continue;
    const text = message.content.toLowerCase();
    if (
      text.includes("respond in russian") ||
      text.includes("reply in russian") ||
      text.includes("na russkom")
    ) {
      return "ru";
    }
    if (text.includes("respond in english") || text.includes("reply in english")) {
      return "en";
    }
  }

  const lastUser = [...messages].reverse().find((item) => item.role === "user")?.content ?? "";
  if (/[\u0400-\u04FF]/.test(lastUser)) return "ru";
  return fallback;
}

