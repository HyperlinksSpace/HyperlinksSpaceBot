import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

import 'wallet_storage.dart';
import 'wallet_types.dart';

class WalletServiceImpl implements WalletService {
  static final Ed25519 _ed25519 = Ed25519();

  final WalletStorage _storage;

  WalletServiceImpl({WalletStorage? storage})
      : _storage = storage ?? WalletStorage();

  @override
  Future<WalletMaterial> getOrCreate() async {
    final existing = await getExisting();
    if (existing != null) return existing;

    final mnemonic = bip39.generateMnemonic(strength: 256);
    await _storage.writeMnemonic(mnemonic);
    return _materialFromMnemonic(mnemonic);
  }

  @override
  Future<WalletMaterial?> getExisting() async {
    final mnemonic = await _storage.readMnemonic();
    if (mnemonic == null || mnemonic.trim().isEmpty) return null;
    return _materialFromMnemonic(mnemonic);
  }

  @override
  Future<void> clear() {
    return _storage.clearMnemonic();
  }

  Future<WalletMaterial> _materialFromMnemonic(String mnemonic) async {
    final normalized = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      throw StateError('Mnemonic is empty');
    }

    final seedBytes = bip39.mnemonicToSeed(normalized);
    final seed32 = Uint8List.fromList(seedBytes.sublist(0, 32));
    final keyPair = await _ed25519.newKeyPairFromSeed(seed32);
    final keyData = await keyPair.extract();

    return WalletMaterial(
      mnemonicWords: words,
      publicKeyHex: _toHex(keyData.publicKey.bytes),
    );
  }

  String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
