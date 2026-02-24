import 'package:flutter/material.dart';

import '../app/theme/app_theme.dart';
import 'wallet_service.dart';
import 'wallet_types.dart';

/// Shows [child] when wallet is absent or already unlocked; shows PIN entry when wallet exists but locked (Tonkeeper-style).
///
/// The wallet check runs in the background after first paint so app load is never blocked:
/// - [hasWallet] = storage has encrypted blob or legacy mnemonic (a few key reads).
/// - [getExisting] = in-memory session material (sync).
/// Only when both "has wallet" and "no session" do we show the PIN screen.
class WalletUnlockGate extends StatefulWidget {
  const WalletUnlockGate({super.key, required this.child});

  final Widget child;

  @override
  State<WalletUnlockGate> createState() => _WalletUnlockGateState();
}

class _WalletUnlockGateState extends State<WalletUnlockGate> {
  final WalletServiceImpl _service = WalletServiceImpl();
  /// null = not yet known; true/false after background check.
  bool? _hasWallet;
  bool _unlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// Runs after first frame. Does not block app load; only updates state when done.
  /// - No wallet in storage → create one (getOrCreate), then show app (session is set).
  /// - Wallet exists, no session → in browser try "remember me" payload; else show PIN screen.
  /// - Wallet exists, session → show app.
  Future<void> _check() async {
    try {
      bool has = await _service.hasWallet();
      WalletMaterial? material = await _service.getExisting();

      if (!has) {
        final result = await _service.getOrCreate();
        material = result.material;
        has = material != null;
      } else if (material == null) {
        final restored = await _service.tryRestoreSessionFromStorage();
        if (restored) material = await _service.getExisting();
      }

      if (!mounted) return;
      setState(() {
        _hasWallet = has;
        _unlocked = material != null;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _hasWallet = false;
        _unlocked = false;
      });
      assert(() {
        // ignore: avoid_print
        print('[WalletUnlockGate] _check failed: $e\n$st');
        return true;
      }());
    }
  }

  Future<void> _onPinSubmit(String pin) async {
    setState(() => _error = null);
    try {
      await _service.unlock(pin);
      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Wrong PIN. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show app until we know for sure that wallet exists and is locked (no session).
    if (_hasWallet != true || _unlocked) {
      return widget.child;
    }
    return _PinEntryScreen(
      error: _error,
      onSubmit: _onPinSubmit,
    );
  }
}

class _PinEntryScreen extends StatefulWidget {
  const _PinEntryScreen({this.error, required this.onSubmit});

  final String? error;
  final Future<void> Function(String pin) onSubmit;

  @override
  State<_PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<_PinEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (pin.length != 6) return;
    setState(() => _submitting = true);
    await widget.onSubmit(pin);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Enter your 6-digit PIN',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppTheme.textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your wallet is locked. Enter the PIN you saved when creating the wallet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textColor.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  errorText: widget.error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () {
                        if (_controller.text.trim().length == 6) _submit();
                      },
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
