/**
 * KMS environment and SA key path resolution — no @google-cloud/kms import.
 * (Renamed from kmsEnv.ts — avoid `kms` in path; vercel dev can hang loading those modules.)
 */

import fs from 'node:fs';
import path from 'node:path';

function toWindowsPathIfGitBash(p: string): string {
  if (process.platform === 'win32' && /^\/[a-zA-Z]\//.test(p)) {
    const drive = p[1]!.toUpperCase();
    return path.normalize(`${drive}:${p.slice(2)}`);
  }
  return p;
}

export function resolveServiceAccountKeyPath(): string | undefined {
  const cwdRaw = process.cwd();
  const cwd = typeof cwdRaw === 'string' && cwdRaw.length > 0 ? cwdRaw : '.';
  const envPath = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  const candidates: string[] = [];

  if (envPath) {
    const win = toWindowsPathIfGitBash(envPath);
    if (path.isAbsolute(win)) {
      candidates.push(path.normalize(win));
    } else {
      candidates.push(path.resolve(cwd, win));
    }
    if (win !== envPath) {
      candidates.push(path.resolve(cwd, envPath));
    }
  }

  candidates.push(path.resolve(cwd, 'wallet-kms-unwrap-sa-key.json'));

  const seen = new Set<string>();
  for (const c of candidates) {
    if (!c || seen.has(c)) continue;
    seen.add(c);
    try {
      if (fs.existsSync(c) && fs.statSync(c).isFile()) {
        return c;
      }
    } catch {
      /* ignore */
    }
  }
  return undefined;
}

export function getKmsKeyName(): string {
  return (
    process.env.GCP_KMS_KEY_NAME?.trim() ||
    'projects/hyperlinksspacebot/locations/us-central1/keyRings/wallet-envelope/cryptoKeys/wallet-kek'
  );
}

export function getKmsUsesRestTransport(): boolean {
  if (process.env.GCP_KMS_USE_GRPC === '1') return false;
  if (process.env.GCP_KMS_USE_REST === '0') return false;
  if (process.env.GCP_KMS_USE_REST === '1') return true;
  return true;
}

export function hasExplicitKmsJsonCredentials(): boolean {
  return Boolean(process.env.GCP_SERVICE_ACCOUNT_JSON?.trim());
}

/**
 * Option B (Vercel / serverless): full service account JSON in `GCP_SERVICE_ACCOUNT_JSON`.
 * Parsed once per process; passed to `KeyManagementServiceClient({ credentials })` in envelope-client.
 */
export type ParsedServiceAccountJson =
  | { ok: true; credentials: Record<string, unknown> }
  | {
      ok: false;
      error: 'missing' | 'invalid_json' | 'invalid_shape';
      message: string;
    };

export function parseGcpServiceAccountJson(): ParsedServiceAccountJson {
  const raw = process.env.GCP_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) {
    return {
      ok: false,
      error: 'missing',
      message: 'GCP_SERVICE_ACCOUNT_JSON is unset or empty',
    };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return {
      ok: false,
      error: 'invalid_json',
      message: `JSON.parse failed: ${msg}`,
    };
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return {
      ok: false,
      error: 'invalid_shape',
      message: 'Expected a JSON object (service account key)',
    };
  }
  const o = parsed as Record<string, unknown>;
  if (typeof o.client_email !== 'string' || !o.client_email.includes('@')) {
    return {
      ok: false,
      error: 'invalid_shape',
      message: 'Missing or invalid client_email',
    };
  }
  if (
    typeof o.private_key !== 'string' ||
    !/BEGIN [A-Z ]*PRIVATE KEY/.test(o.private_key)
  ) {
    return {
      ok: false,
      error: 'invalid_shape',
      message: 'Missing or invalid private_key',
    };
  }
  return { ok: true, credentials: o };
}

/** Which credential path `getKmsClient()` will use (see envelope-client.ts). */
export function getKmsCredentialSource():
  | 'json_env'
  | 'json_env_invalid'
  | 'key_file'
  | 'adc' {
  const p = parseGcpServiceAccountJson();
  if (p.ok) return 'json_env';
  if (p.error !== 'missing') return 'json_env_invalid';
  if (resolveServiceAccountKeyPath()) return 'key_file';
  return 'adc';
}
