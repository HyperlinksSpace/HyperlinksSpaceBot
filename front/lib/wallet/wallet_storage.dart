import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import '../telegram_webapp.dart';

class WalletStorage {
  static const String mnemonicKey = 'wallet_mnemonic';

  final TelegramWebApp _telegram;

  WalletStorage({TelegramWebApp? telegramWebApp})
      : _telegram = telegramWebApp ?? TelegramWebApp();

  bool get isTelegram => _telegram.isActuallyInTelegram;

  Future<String?> readMnemonic() async {
    if (_telegram.isActuallyInTelegram) {
      final secure = await _secureGet(mnemonicKey);
      return _isSet(secure) ? secure!.trim() : null;
    }
    final local = html.window.localStorage[mnemonicKey];
    return _isSet(local) ? local!.trim() : null;
  }

  Future<void> writeMnemonic(String mnemonic) async {
    final trimmed = mnemonic.trim();
    if (trimmed.isEmpty) return;

    if (_telegram.isActuallyInTelegram) {
      await _secureSet(mnemonicKey, trimmed);
      return;
    }
    html.window.localStorage[mnemonicKey] = trimmed;
  }

  Future<void> clearMnemonic() async {
    if (_telegram.isActuallyInTelegram) {
      await _secureDelete(mnemonicKey);
      return;
    }
    html.window.localStorage.remove(mnemonicKey);
  }

  Future<String?> _secureGet(String key) async {
    final app = _telegram.webApp;
    if (app == null) return null;

    for (final objectName in ['SecureStorage', 'secureStorage']) {
      final secure = app[objectName];
      if (secure is! js.JsObject) continue;
      final value = await _jsGetItem(secure, key);
      if (_isSet(value)) return value!.trim();
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

  Future<void> _secureDelete(String key) async {
    final app = _telegram.webApp;
    if (app == null) return;

    for (final objectName in ['SecureStorage', 'secureStorage']) {
      final secure = app[objectName];
      if (secure is! js.JsObject) continue;
      final removeItem = secure['removeItem'];
      if (removeItem is js.JsFunction) {
        final completer = Completer<void>();
        try {
          removeItem.apply([
            key,
            (dynamic _, [dynamic __]) {
              if (!completer.isCompleted) completer.complete();
            }
          ]);
          await completer.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
          return;
        } catch (_) {
          if (!completer.isCompleted) completer.complete();
        }
      }
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

  bool _isSet(String? value) => value != null && value.trim().isNotEmpty;
}
