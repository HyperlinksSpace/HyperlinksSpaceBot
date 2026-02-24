import 'dart:async';
import 'dart:math';

import 'package:blockchain_utils/blockchain_utils.dart'
    show Mnemonic, TonMnemonicGenerator, TonSeedGenerator;
import 'package:ton_dart/ton_dart.dart';

import 'wallet_crypto.dart';
import 'wallet_storage.dart';
import 'wallet_types.dart';

/// Delimiter between mnemonic and seed password in encrypted payload.
const String _payloadSeparator = '\n';

class WalletServiceImpl implements WalletService {
  WalletServiceImpl({WalletStorage? storage})
      : _storage = storage ?? WalletStorage();

  final WalletStorage _storage;

  WalletMaterial? _sessionMaterial;
  String? _sessionPin;

  @override
  Future<bool> hasWallet() async {
    final enc = await _storage.readEncrypted();
    if (enc != null && enc.isNotEmpty) return true;
    final m = await _storage.readMnemonic();
    final p = await _storage.readMnemonicPassword();
    return (m != null && m.trim().isNotEmpty) &&
        (p != null && p.trim().isNotEmpty);
  }

  @override
  Future<WalletCreateResult> getOrCreate() async {
    final encrypted = await _storage.readEncrypted();
    if (encrypted != null && encrypted.isNotEmpty) {
      return const WalletCreateResult(null, null);
    }

    final mnemonic = await _storage.readMnemonic();
    final password = await _storage.readMnemonicPassword();
    final hasLegacy =
        mnemonic != null && mnemonic.trim().isNotEmpty && password != null && password.trim().isNotEmpty;

    if (hasLegacy) {
      return _migrateLegacy(mnemonic.trim(), password.trim());
    }

    return _createNew();
  }

  @override
  Future<WalletMaterial?> getExisting() async {
    return _sessionMaterial;
  }

  @override
  Future<WalletMaterial> unlock(String pin) async {
    final encrypted = await _storage.readEncrypted();
    if (encrypted == null || encrypted.isEmpty) {
      throw StateError('No encrypted wallet');
    }
    final plain = await walletDecrypt(encrypted, pin);
    final idx = plain.indexOf(_payloadSeparator);
    if (idx < 0) throw FormatException('Invalid payload');
    final mnemonic = plain.substring(0, idx).trim();
    final password = plain.substring(idx + _payloadSeparator.length).trim();
    final material = await _materialFromMnemonicAndPassword(mnemonic, password);
    _sessionMaterial = material;
    _sessionPin = pin;
    if (!_storage.isTelegram) {
      await _storage.writeSessionPayload(plain);
    }
    return material;
  }

  @override
  String? getSessionPin() => _sessionPin;

  @override
  void lock() {
    _sessionMaterial = null;
    _sessionPin = null;
    unawaited(_storage.clearSessionPayload());
  }

  /// Browser only: restore session from "remember me" payload so we skip PIN on load.
  Future<bool> tryRestoreSessionFromStorage() async {
    if (_storage.isTelegram) return false;
    final payload = await _storage.readSessionPayload();
    if (payload == null || payload.isEmpty) return false;
    final idx = payload.indexOf(_payloadSeparator);
    if (idx < 0) return false;
    try {
      final mnemonic = payload.substring(0, idx).trim();
      final password = payload.substring(idx + _payloadSeparator.length).trim();
      final material = await _materialFromMnemonicAndPassword(mnemonic, password);
      _sessionMaterial = material;
      _sessionPin = null;
      return true;
    } catch (_) {
      await _storage.clearSessionPayload();
      return false;
    }
  }

  @override
  Future<void> clear() async {
    lock();
    await _storage.clearSessionPayload();
    await _storage.clearEncrypted();
    await _storage.setLock(false);
    await _storage.clearMnemonic();
    await _storage.clearMnemonicPassword();
  }

  Future<WalletCreateResult> _createNew() async {
    final password = _generateRandomPassword();
    final mnemonicGenerated =
        TonMnemonicGenerator().fromWordsNumber(24, password: password);
    final mnemonicString = _mnemonicToString(mnemonicGenerated);
    final pin = _generatePin();
    final payload = '$mnemonicString$_payloadSeparator$password';
    final cipher = await walletEncrypt(payload, pin);
    await _storage.writeEncrypted(cipher);
    await _storage.clearMnemonic();
    await _storage.clearMnemonicPassword();
    final material =
        await _materialFromMnemonicAndPassword(mnemonicString, password);
    _sessionMaterial = material;
    _sessionPin = pin;
    if (!_storage.isTelegram) {
      await _storage.writeSessionPayload(payload);
    }
    return WalletCreateResult(material, pin);
  }

  Future<WalletCreateResult> _migrateLegacy(String mnemonic, String password) async {
    final pin = _generatePin();
    final payload = '$mnemonic$_payloadSeparator$password';
    final cipher = await walletEncrypt(payload, pin);
    await _storage.writeEncrypted(cipher);
    await _storage.clearMnemonic();
    await _storage.clearMnemonicPassword();
    final material =
        await _materialFromMnemonicAndPassword(mnemonic, password);
    _sessionMaterial = material;
    _sessionPin = pin;
    if (!_storage.isTelegram) {
      await _storage.writeSessionPayload(payload);
    }
    return WalletCreateResult(material, pin);
  }

  static String _generatePin({int digits = 6}) {
    final rand = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < digits; i++) {
      sb.write(rand.nextInt(10));
    }
    return sb.toString();
  }

  Future<WalletMaterial> _materialFromMnemonicAndPassword(
      String mnemonic, String password) async {
    final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      throw StateError('Mnemonic is empty');
    }

    final mnemonicObj = Mnemonic.fromString(normalized);
    final seed = TonSeedGenerator(mnemonicObj)
        .generate(password: password, validateTonMnemonic: true);
    final privateKey = TonPrivateKey.fromBytes(seed);
    final publicKey = privateKey.toPublicKey();
    final publicKeyBytes = publicKey.toBytes();

    final wallet = WalletV4.create(
      chain: TonChainId.mainnet,
      publicKey: publicKeyBytes,
      bounceableAddress: true,
    );
    final address = wallet.address.toString();

    return WalletMaterial(
      mnemonicWords: words,
      publicKeyHex: _toHex(publicKeyBytes),
      address: address,
    );
  }

  String _generateRandomPassword({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    final codeUnits = List<int>.generate(
      length,
      (_) => chars.codeUnitAt(rand.nextInt(chars.length)),
    );
    return String.fromCharCodes(codeUnits);
  }

  String _mnemonicToString(dynamic mnemonic) {
    if (mnemonic is Mnemonic) return mnemonic.toString();
    if (mnemonic is List<String>) return mnemonic.join(' ');
    return mnemonic.toString();
  }

  String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
