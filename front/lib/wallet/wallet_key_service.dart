import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

import 'package:cryptography/cryptography.dart';

import '../telegram_webapp.dart';

class KeyPair {
  final String publicKeyBase64;
  final String privateKeyBase64;

  const KeyPair({
    required this.publicKeyBase64,
    required this.privateKeyBase64,
  });
}

class WalletKeyService {
  static const String _privKey = 'wallet_priv';
  static const String _pubKey = 'wallet_pub';

  static final Ed25519 _ed25519 = Ed25519();

  final TelegramWebApp _telegram;

  WalletKeyService({TelegramWebApp? telegramWebApp})
      : _telegram = telegramWebApp ?? TelegramWebApp();

  Future<KeyPair> getOrCreateKeyPair() async {
    try {
      if (_telegram.isActuallyInTelegram) {
        final existingPriv = await _secureGet(_privKey);
        final existingPub = await _secureGet(_pubKey);
        if (_isSet(existingPriv) && _isSet(existingPub)) {
          return KeyPair(
            privateKeyBase64: existingPriv!.trim(),
            publicKeyBase64: existingPub!.trim(),
          );
        }
      }
    } catch (e) {
      print('[WalletKeyService] secure read failed: $e');
    }

    final generated = await _generate();

    if (_telegram.isActuallyInTelegram) {
      try {
        await _secureSet(_privKey, generated.privateKeyBase64);
        await _secureSet(_pubKey, generated.publicKeyBase64);
      } catch (e) {
        // Storage failure must not block app flow.
        print('[WalletKeyService] secure write failed: $e');
      }
    }

    return generated;
  }

  Future<KeyPair> _generate() async {
    final keyPair = await _ed25519.newKeyPair();
    final keyData = await keyPair.extract();
    return KeyPair(
      privateKeyBase64: base64Encode(keyData.privateKeyBytes),
      publicKeyBase64: base64Encode(keyData.publicKey.bytes),
    );
  }

  Future<String?> _secureGet(String key) async {
    final app = _telegram.webApp;
    if (app == null) return null;

    for (final objectName in ['SecureStorage', 'secureStorage']) {
      final secure = app[objectName];
      if (secure is! js.JsObject) continue;
      final value = await _jsGetItem(secure, key);
      if (value != null) return value;
    }
    return null;
  }

  Future<void> _secureSet(String key, String value) async {
    final app = _telegram.webApp;
    if (app == null) return;

    for (final objectName in ['SecureStorage', 'secureStorage']) {
      final secure = app[objectName];
      if (secure is! js.JsObject) continue;
      final ok = await _jsSetItem(secure, key, value);
      if (ok) return;
    }
  }

  Future<String?> _jsGetItem(js.JsObject object, String key) async {
    final completer = Completer<String?>();
    try {
      final getItem = object['getItem'];
      if (getItem is js.JsFunction) {
        getItem.apply([
          key,
          (dynamic error, dynamic value) {
            if (completer.isCompleted) return;
            if (error != null) {
              completer.complete(null);
              return;
            }
            completer.complete(value?.toString());
          }
        ]);
      } else {
        completer.complete(null);
      }
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  Future<bool> _jsSetItem(js.JsObject object, String key, String value) async {
    final completer = Completer<bool>();
    try {
      final setItem = object['setItem'];
      if (setItem is js.JsFunction) {
        setItem.apply([
          key,
          value,
          (dynamic error, [dynamic _]) {
            if (completer.isCompleted) return;
            completer.complete(error == null);
          }
        ]);
      } else {
        completer.complete(false);
      }
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
  }

  bool _isSet(String? v) => v != null && v.trim().isNotEmpty;
}
