/**
 * GET /api/wallet-envelope-probe — zero-import smoke test.
 * Public **`/api/kmsprobe`** (rewrite in vercel.json).
 *
 * Supports legacy Node `res` like `ping.ts` — `vercel dev` may pass `res` and expect
 * `res.end()` instead of returning a Web `Response`.
 */

type NodeRes = {
  setHeader(name: string, value: string): void;
  status(code: number): void;
  end(body?: string): void;
};

async function handler(
  _request: Request,
  res?: NodeRes,
): Promise<Response | void> {
  const body = JSON.stringify({
    ok: true,
    route: '/api/kmsprobe',
    handler: 'api/wallet-envelope-probe.ts',
  });

  if (res) {
    res.setHeader('Content-Type', 'application/json');
    res.status(200);
    res.end(body);
    return;
  }

  return new Response(body, {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default handler;
export const GET = handler;
