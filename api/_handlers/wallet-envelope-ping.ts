/**
 * GET /api/wallet-envelope-ping — fast probe / usage / diag.
 *
 * Public URLs **`/api/kmsping`**, **`/api/kms/ping`**, **`/api/kms-ping`** rewrite here (`vercel.json`).
 * Lib: **`envelope-*.ts`** (see `infra/gcp/backend-authentication.md`).
 *
 * Supports legacy Node `res` like `ping.ts` — `vercel dev` may pass `res` and expect
 * `res.end()` instead of returning a Web `Response`.
 */

import {
  getKmsCredentialSource,
  getKmsKeyName,
  getKmsUsesRestTransport,
  hasExplicitKmsJsonCredentials,
  parseGcpServiceAccountJson,
  resolveServiceAccountKeyPath,
} from '../_lib/envelope-env.js';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

type NodeRes = {
  setHeader(name: string, value: string): void;
  status(code: number): void;
  end(body?: string): void;
};

function parseRequestUrl(request: Request): URL {
  const raw = request.url;
  if (!raw) {
    return new URL('http://127.0.0.1/api/kmsping');
  }
  try {
    return new URL(raw);
  } catch {
    return new URL(raw, 'http://127.0.0.1');
  }
}

function sendJson(
  res: NodeRes | undefined,
  body: object,
  status: number,
): Response | void {
  const json = JSON.stringify(body);
  if (res) {
    res.setHeader('Content-Type', 'application/json');
    res.status(status);
    res.end(json);
    return;
  }
  return new Response(json, { status, headers: JSON_HEADERS });
}

async function handler(
  request: Request,
  res?: NodeRes,
): Promise<Response | void> {
  const method = request.method ?? 'GET';
  if (method !== 'GET') {
    if (res) {
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
      res.status(405);
      res.end('Method Not Allowed');
      return;
    }
    return new Response('Method Not Allowed', { status: 405 });
  }

  const url = parseRequestUrl(request);

  if (url.searchParams.get('probe') === '1') {
    return sendJson(
      res,
      {
        ok: true,
        probe: true,
        ts: Date.now(),
        hint: 'Try ?diag=1 — KMS: /api/kms-roundtrip?quick=1 or ?roundtrip=1',
      },
      200,
    );
  }

  if (url.searchParams.get('diag') === '1') {
    const keyPath = resolveServiceAccountKeyPath();
    const jsonParse = parseGcpServiceAccountJson();
    return sendJson(
      res,
      {
        ok: true,
        diag: true,
        cwd: process.cwd(),
        vercelEnv: process.env.VERCEL_ENV ?? null,
        credentialSource: getKmsCredentialSource(),
        hasGcpServiceAccountJson: hasExplicitKmsJsonCredentials(),
        gcpServiceAccountJson:
          jsonParse.ok ? 'ok' : jsonParse.error === 'missing' ? 'absent' : 'invalid',
        gcpServiceAccountJsonError:
          jsonParse.ok || jsonParse.error === 'missing' ? null : jsonParse.message,
        resolvedKeyPath: keyPath ?? null,
        keyFileExists: Boolean(keyPath),
        kmsTransport: getKmsUsesRestTransport() ? 'rest' : 'grpc',
        keyName: getKmsKeyName(),
        hint: 'Next: GET /api/kms-roundtrip?quick=1 or ?roundtrip=1',
      },
      200,
    );
  }

  const wantsQuick = url.searchParams.get('quick') === '1';
  const wantsRoundtrip =
    url.searchParams.get('roundtrip') === '1' ||
    url.searchParams.get('full') === '1';

  if (wantsQuick || wantsRoundtrip) {
    const dest = new URL(url.toString());
    dest.pathname = '/api/kms-roundtrip';
    return sendJson(
      res,
      {
        ok: false,
        error: 'wrong_route',
        message:
          'KMS lives in route wallet-envelope-roundtrip / public /api/kms-roundtrip. Call:',
        url: dest.toString(),
        curl: `curl -s --max-time 120 "${dest.toString()}"`,
      },
      422,
    );
  }

  return sendJson(
    res,
    {
      ok: true,
      usage: true,
      handler: 'api/[...path].ts (wallet-envelope-ping)',
      message:
        'KMS crypto is in route wallet-envelope-roundtrip (api/[...path].ts); shared code in api/_lib/envelope-*.ts.',
      try: {
        probe: '/api/kmsping?probe=1',
        diag: '/api/kmsping?diag=1',
        encryptOnly: '/api/kms-roundtrip?quick=1',
        encryptAndDecrypt:
          '/api/kms-roundtrip?roundtrip=1  (curl -s --max-time 120 "...")',
      },
    },
    200,
  );
}

export default handler;
export const GET = handler;
