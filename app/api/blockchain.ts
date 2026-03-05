/**
 * Minimal blockchain gateway.
 * GET /api/blockchain → status of blockchain integrations (swap.coffee, etc.).
 *
 * Supports both:
 * - Web API style (Request → Response)
 * - Legacy Node style (req, res)
 */

import { handleBlockchainRequest } from "../blockchain/router.js";

type NodeRes = {
  setHeader(name: string, value: string): void;
  status(code: number): void;
  end(body?: string): void;
};

function jsonResponse(body: object, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function handler(
  request: Request,
  res?: NodeRes,
): Promise<Response | void> {
  const method = (request as any)?.method ?? "GET";

  if (method !== "GET") {
    const body = { ok: false, error: "Method not allowed" };

    if (res) {
      res.setHeader("Content-Type", "application/json");
      res.status(405);
      res.end(JSON.stringify(body));
      return;
    }

    return jsonResponse(body, 405);
  }

  const result = await handleBlockchainRequest({ mode: "ping" });

  if (res) {
    res.setHeader("Content-Type", "application/json");
    res.status(200);
    res.end(JSON.stringify(result));
    return;
  }

  return jsonResponse(result, 200);
}

export default handler;
export const GET = handler;

