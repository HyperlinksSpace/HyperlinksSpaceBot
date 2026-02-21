import 'dart:async';

import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../telegram_webapp.dart';
import '../wallet/wallet_service.dart';

class BootstrapScreen extends StatefulWidget {
  final Widget home;

  const BootstrapScreen({super.key, required this.home});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Run in background: layout is already visible
    _run();
  }

  Future<void> _run() async {
    try {
      final webApp = TelegramWebApp();
      final initData = webApp.initDataString?.trim() ?? '';

      // Outside Telegram (browser): no sign-in. Skip auth when:
      // - URL has ?standalone=1 (explicit browser mode), or
      // - not actually in Telegram, or
      // - no initData (cannot authenticate without it)
      final bool standaloneMode = Uri.base.queryParameters['standalone'] == '1';
      final bool skipSignIn = standaloneMode || !webApp.isActuallyInTelegram || initData.isEmpty;
      if (skipSignIn) {
        _warmUpWallet();
        return;
      }

      _warmUpWallet();

      // Prefer async resolve so production can get BOT_API_URL from /api/config (Vercel env)
      String baseUrl = AuthApi.resolveBaseUrl();
      if (baseUrl.isEmpty) {
        baseUrl = await AuthApi.resolveBaseUrlAsync();
      }
      if (baseUrl.isEmpty) {
        if (!mounted) return;
        setState(() => _error =
            'Service URL is not configured. '
            'Local: run the app via the repo start script (start.sh / start.ps1) or set BOT_API_URL in front/.env. '
            'Production: set BOT_API_URL in Vercel (or host) environment.');
        return;
      }

      final authApi = AuthApi(baseUrl: baseUrl);
      await authApi.authTelegram(initData: initData);
      // Success: no navigation needed, layout is already shown
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    }
  }

  void _warmUpWallet() {
    unawaited(() async {
      try {
        final material = await WalletServiceImpl().getOrCreate();
        final preview = material.publicKeyHex.length <= 8
            ? material.publicKeyHex
            : material.publicKeyHex.substring(0, 8);
        print('[Wallet] keypair ready pub=$preview...');
      } catch (e) {
        // Never block app load if wallet key setup fails.
        print('[Wallet] material warm-up failed: $e');
      }
    }());
  }

  String _humanizeError(Object e) {
    if (e is AuthException) {
      switch (e.error) {
        case 'invalid_initdata':
          return 'Auth failed. Please open this app from Telegram.';
        case 'username_required':
          return 'Your Telegram account has no username. Set one in Telegram settings and try again.';
        case 'db_unavailable':
          return 'Service is temporarily unavailable. Try again in a minute.';
        default:
          return 'Could not sign you in. (${e.error})';
      }
    }
    return 'Could not sign you in. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layout loads first; bootstrap (URL, auth) runs in background
        widget.home,
        if (_error != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              elevation: 4,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _run();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
