import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const int _nonceLength = 12;
const int _macLength = 16;

/// Encrypts [plaintext] with a key derived from [pin] (Tonkeeper-style:
/// SHA-256 of PIN + AES-256-GCM with random nonce).
/// Returns base64(nonce + ciphertext + mac) via SecretBox.concatenation().
Future<String> walletEncrypt(String plaintext, String pin) async {
  final key = await _pinToKey(pin);
  final algorithm = AesGcm.with256bits();
  final secretBox = await algorithm.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
  );
  final combined = secretBox.concatenation();
  return base64Url.encode(combined);
}

/// Decrypts [ciphertextBase64] with [pin]. Throws on wrong PIN or corrupt data.
Future<String> walletDecrypt(String ciphertextBase64, String pin) async {
  final key = await _pinToKey(pin);
  final bytes = base64Url.decode(ciphertextBase64);
  if (bytes.length < _nonceLength + _macLength) {
    throw FormatException('Invalid ciphertext');
  }
  final secretBox = SecretBox.fromConcatenation(
    bytes,
    nonceLength: _nonceLength,
    macLength: _macLength,
    copy: false,
  );
  final algorithm = AesGcm.with256bits();
  final plain = await algorithm.decrypt(
    secretBox,
    secretKey: key,
  );
  return utf8.decode(plain);
}

Future<SecretKey> _pinToKey(String pin) async {
  final h = Sha256();
  final digest = await h.hash(utf8.encode(pin));
  return SecretKey(digest.bytes);
}
