import { handleChat } from "../bot/handler.js";
import type { ChatMessage } from "../bot/openapi.js";

type ChatRequestBody = {
  messages?: ChatMessage[];
  tokenHint?: string;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, X-API-Key",
    },
  });
}

function readApiKey(headers: Headers): string {
  return (headers.get("x-api-key") || "").trim();
}

function expectedApiKey(): string {
  return (process.env.INNER_CALLS_KEY || "").trim();
}

function isAuthorized(headers: Headers): boolean {
  const expected = expectedApiKey();
  if (!expected) return true;
  return readApiKey(headers) === expected;
}

function normalizeBody(payload: ChatRequestBody): { messages: ChatMessage[]; tokenHint?: string } {
  const messages = Array.isArray(payload.messages)
    ? payload.messages.filter((message) =>
        message &&
        (message.role === "system" || message.role === "user" || message.role === "assistant") &&
        typeof message.content === "string"
      )
    : [];

  return {
    messages: messages.length > 0 ? messages : [{ role: "user", content: "" }],
    tokenHint: typeof payload.tokenHint === "string" ? payload.tokenHint : undefined,
  };
}

export async function OPTIONS(): Promise<Response> {
  return json({}, 200);
}

export async function POST(request: Request): Promise<Response> {
  if (!isAuthorized(request.headers)) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  let body: ChatRequestBody;
  try {
    body = (await request.json()) as ChatRequestBody;
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  const normalized = normalizeBody(body);

  try {
    const result = await handleChat(normalized);
    return json({ ok: true, text: result.text, meta: result.meta }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    return json({ ok: false, error: message }, 500);
  }
}

export default POST;

