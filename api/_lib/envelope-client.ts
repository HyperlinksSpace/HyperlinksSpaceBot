/**
 * Cloud KMS client for wallet envelope KEK (encrypt/decrypt DEK material).
 * Loads `@google-cloud/kms` only when `getKmsClient()` runs (dynamic import).
 *
 * See `envelope-env.ts` for credentials env vars and path rules.
 */

import type { KeyManagementServiceClient } from '@google-cloud/kms';
import {
  getKmsUsesRestTransport,
  parseGcpServiceAccountJson,
  resolveServiceAccountKeyPath,
} from './envelope-env.js';

let client: KeyManagementServiceClient | null = null;

export async function getKmsClient(): Promise<KeyManagementServiceClient> {
  if (client) {
    return client;
  }

  const { KeyManagementServiceClient } = await import('@google-cloud/kms');
  const useRestTransport = getKmsUsesRestTransport();

  const parsed = parseGcpServiceAccountJson();
  if (parsed.ok) {
    client = new KeyManagementServiceClient({
      credentials: parsed.credentials,
      fallback: useRestTransport,
    });
    return client;
  }
  if (parsed.error !== 'missing') {
    throw new Error(
      `GCP_SERVICE_ACCOUNT_JSON is set but invalid: ${parsed.message}`,
    );
  }

  const keyFile = resolveServiceAccountKeyPath();
  if (keyFile) {
    client = new KeyManagementServiceClient({
      keyFilename: keyFile,
      fallback: useRestTransport,
    });
    return client;
  }

  client = new KeyManagementServiceClient({ fallback: useRestTransport });
  return client;
}

export {
  getKmsCredentialSource,
  getKmsKeyName,
  getKmsUsesRestTransport,
  hasExplicitKmsJsonCredentials,
  parseGcpServiceAccountJson,
  resolveServiceAccountKeyPath,
} from './envelope-env.js';
