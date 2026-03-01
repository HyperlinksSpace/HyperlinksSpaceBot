import type { ChatMessage, LlmChatRequest, LlmStreamChunk } from "./types.js";

type OpenAiOptions = {
  apiKey: string;
  model?: string;
  baseUrl?: string;
  timeoutMs?: number;
};

export interface LlmClient {
  complete(request: LlmChatRequest): Promise<string>;
  stream?(request: LlmChatRequest): AsyncGenerator<LlmStreamChunk>;
}

export class OpenAiLlmClient implements LlmClient {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor(options: OpenAiOptions) {
    this.apiKey = options.apiKey;
    this.model = options.model ?? "gpt-4o-mini";
    this.baseUrl = (options.baseUrl ?? "https://api.openai.com/v1").replace(/\/$/, "");
    this.timeoutMs = options.timeoutMs ?? 35_000;
  }

  async complete(request: LlmChatRequest): Promise<string> {
    const payload = {
      model: request.model || this.model,
      messages: toOpenAiMessages(request.messages),
      temperature: request.temperature,
      stream: false,
    };

    const response = await this.request("/chat/completions", payload);
    const data = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    return data.choices?.[0]?.message?.content?.trim() ?? "";
  }

  async *stream(request: LlmChatRequest): AsyncGenerator<LlmStreamChunk> {
    const payload = {
      model: request.model || this.model,
      messages: toOpenAiMessages(request.messages),
      temperature: request.temperature,
      stream: true,
    };

    const response = await this.request("/chat/completions", payload);
    const body = response.body;
    if (!body) {
      yield { error: "OpenAI stream body is missing", done: true };
      return;
    }

    const reader = body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let ended = false;

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const events = splitSseEvents(buffer);
      buffer = events.remainder;

      for (const event of events.events) {
        const parsed = parseSseDataLine(event);
        if (!parsed) continue;
        if (parsed === "[DONE]") {
          ended = true;
          break;
        }

        try {
          const payloadJson = JSON.parse(parsed) as {
            choices?: Array<{ delta?: { content?: string } }>;
          };
          const token = payloadJson.choices?.[0]?.delta?.content;
          if (typeof token === "string" && token.length > 0) yield { token };
        } catch {
          // Ignore malformed chunks from upstream and keep stream alive.
        }
      }

      if (ended) break;
    }

    yield { done: true };
  }

  private async request(path: string, payload: Record<string, unknown>): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}${path}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      if (!response.ok) {
        const detail = await response.text();
        throw new Error(`OpenAI error ${response.status}: ${detail.slice(0, 500)}`);
      }
      return response;
    } finally {
      clearTimeout(timeout);
    }
  }
}

function toOpenAiMessages(messages: ChatMessage[]): Array<{ role: string; content: string }> {
  return messages.map((message) => ({ role: message.role, content: message.content }));
}

function splitSseEvents(raw: string): { events: string[]; remainder: string } {
  const events: string[] = [];
  let start = 0;

  while (start < raw.length) {
    const next = raw.indexOf("\n\n", start);
    if (next === -1) break;
    events.push(raw.slice(start, next));
    start = next + 2;
  }

  return {
    events,
    remainder: raw.slice(start),
  };
}

function parseSseDataLine(event: string): string | undefined {
  const lines = event.split(/\r?\n/);
  const dataLines = lines.filter((line) => line.startsWith("data:"));
  if (dataLines.length === 0) return undefined;
  return dataLines.map((line) => line.slice(5).trim()).join("\n");
}

