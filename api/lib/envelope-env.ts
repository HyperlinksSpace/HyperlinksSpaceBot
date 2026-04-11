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
