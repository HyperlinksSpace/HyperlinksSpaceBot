export type ChatRole = "system" | "user" | "assistant";

export type ChatMessage = {
  role: ChatRole;
  content: string;
};

type OpenAiOptions = {
  apiKey: string;
  model: string;
  baseUrl: string;
  timeoutMs: number;
  enabled: boolean;
  dryRun: boolean;
  maxRequests: number;
};

const options: OpenAiOptions = {
  apiKey: process.env.OPENAI_API_KEY || process.env.OPENAI_KEY || "",
  model: process.env.OPENAI_MODEL || "gpt-4o-mini",
  baseUrl: (process.env.OPENAI_BASE_URL || "https://api.openai.com/v1").replace(/\/$/, ""),
  timeoutMs: Number(process.env.OPENAI_TIMEOUT_MS || 35000),
  enabled: (process.env.OPENAI_ENABLED || "1").trim() === "1",
  dryRun: (process.env.OPENAI_DRY_RUN || "0").trim() === "1",
  maxRequests: Number(process.env.OPENAI_MAX_REQUESTS || 2),
};

let requestCount = 0;

export function getOpenAiGuardState(): { enabled: boolean; dryRun: boolean; requestCount: number; maxRequests: number } {
  return {
    enabled: options.enabled,
    dryRun: options.dryRun,
    requestCount,
    maxRequests: options.maxRequests,
  };
}

export async function callOpenAi(messages: ChatMessage[], temperature = 0.3, modelOverride?: string): Promise<string> {
  if (!options.enabled) {
    throw new Error("OpenAI disabled by OPENAI_ENABLED");
  }

  if (!options.apiKey) {
    throw new Error("Missing OPENAI_API_KEY");
  }

  if (requestCount >= options.maxRequests) {
    throw new Error(`OpenAI request cap reached (${options.maxRequests})`);
  }

  if (options.dryRun) {
    return "[dry-run] OpenAI call skipped.";
  }

  requestCount += 1;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs);

  try {
    const response = await fetch(`${options.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options.apiKey}`,
      },
      body: JSON.stringify({
        model: modelOverride || options.model,
        messages,
        temperature,
        stream: false,
      }),
      signal: controller.signal,
    });

      if (!response.ok) {
        throw new Error(`OpenAI error ${response.status}`);
      }

    const data = (await response.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    return (data.choices?.[0]?.message?.content || "").trim();
  } finally {
    clearTimeout(timeout);
  }
}
