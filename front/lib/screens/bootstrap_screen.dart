import 'package:flutter/material.dart';

import '../api/auth_api.dart';
import '../telegram_webapp.dart';

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
    _run();
  }

  Future<void> _run() async {
    try {
      final webApp = TelegramWebApp();
      final initData = webApp.initDataString?.trim() ?? '';
      if (initData.isEmpty) {
        setState(() => _error = 'Open this app from inside Telegram.');
        return;
      }

      final baseUrl = AuthApi.resolveBaseUrl();
      if (baseUrl.isEmpty) {
        setState(() => _error = 'Service URL is not configured.');
        return;
      }

      final authApi = AuthApi(baseUrl: baseUrl);
      await authApi.authTelegram(initData: initData);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.home),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    }
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
    if (_error == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
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
    );
  }
}
