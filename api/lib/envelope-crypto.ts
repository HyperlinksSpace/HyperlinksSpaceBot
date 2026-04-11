import type { KeyManagementServiceClient } from '@google-cloud/kms';
import { getKmsClient, getKmsKeyName } from './envelope-client.js';

/**
 * Wrap a small secret (e.g. 32-byte DEK) with the KMS KEK.
 * Store returned buffer as wrapped_dek (e.g. base64) in your DB.
 */
export async function kmsEncrypt(
  plaintext: Buffer,
  options?: { client?: KeyManagementServiceClient; keyName?: string },
): Promise<Buffer> {
  const kms = options?.client ?? (await getKmsClient());
  const name = options?.keyName ?? getKmsKeyName();
  const [result] = await kms.encrypt({ name, plaintext });
  if (!result.ciphertext) {
    throw new Error('kms_encrypt_no_ciphertext');
  }
  return Buffer.from(result.ciphertext);
}

/**
 * Unwrap ciphertext produced by kmsEncrypt.
 */
export async function kmsDecrypt(
  ciphertext: Buffer,
  options?: { client?: KeyManagementServiceClient; keyName?: string },
): Promise<Buffer> {
  const kms = options?.client ?? (await getKmsClient());
  const name = options?.keyName ?? getKmsKeyName();
  const [result] = await kms.decrypt({ name, ciphertext });
  if (!result.plaintext) {
    throw new Error('kms_decrypt_no_plaintext');
  }
  return Buffer.from(result.plaintext);
}
