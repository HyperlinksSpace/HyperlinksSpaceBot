import 'dart:typed_data';

import 'package:ton_dart/ton_dart.dart';

/// Derives a TON WalletV4 user-friendly address from an Ed25519 public key (hex).
/// Uses [ton_dart] WalletV4.create flow: public key → WalletV4 → address.
/// Returns null if conversion fails (invalid hex or library error).
String? tonAddressFromPublicKeyHex(String publicKeyHex) {
  try {
    final hex = publicKeyHex.trim().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length % 2 != 0) return null;
    final bytes = _hexToBytes(hex);
    if (bytes.length != 32) return null;

    final wallet = WalletV4.create(
      chain: TonChainId.mainnet,
      publicKey: bytes,
      bounceableAddress: true,
    );
    return wallet.address.toString();
  } catch (_) {
    return null;
  }
}

Uint8List _hexToBytes(String hex) {
  final list = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    list.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(list);
}
