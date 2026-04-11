/**
 * Cloud KMS client for wallet envelope KEK (encrypt/decrypt DEK material).
 * Loads `@google-cloud/kms` only when `getKmsClient()` runs (dynamic import).
 *
 * See `envelope-env.ts` for credentials env vars and path rules.
 */

import type { KeyManagementServiceClient } from '@google-cloud/kms';
import { getKmsUsesRestTransport, resolveServiceAccountKeyPath } from './envelope-env.js';

let client: KeyManagementServiceClient | null = null;

export async function getKmsClient(): Promise<KeyManagementServiceClient> {
  if (client) {
    return client;
  }

  const { KeyManagementServiceClient } = await import('@google-cloud/kms');
  const fallback = getKmsUsesRestTransport();
  const raw = process.env.GCP_SERVICE_ACCOUNT_JSON?.trim();

  if (raw) {
    const credentials = JSON.parse(raw) as Record<string, unknown>;
    client = new KeyManagementServiceClient({ credentials, fallback });
  } else {
    const keyFile = resolveServiceAccountKeyPath();
    if (keyFile) {
      process.env.GOOGLE_APPLICATION_CREDENTIALS = keyFile;
      client = new KeyManagementServiceClient({
        keyFilename: keyFile,
        fallback,
      });
    } else {
      client = new KeyManagementServiceClient({ fallback });
    }
  }

  return client;
}

export {
  getKmsKeyName,
  getKmsUsesRestTransport,
  hasExplicitKmsJsonCredentials,
  resolveServiceAccountKeyPath,
} from './envelope-env.js';
