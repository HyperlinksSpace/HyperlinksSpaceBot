/**
 * Zero-dependency health check. GET /api/ping → { ok: true, ping: true }
 * ESM so it works with "type": "module" (Vercel loads api as ES module).
 */
export default function handler(req, res) {
  res.setHeader('Content-Type', 'application/json');
  res.status(200);
  res.end(JSON.stringify({ ok: true, ping: true }));
}
