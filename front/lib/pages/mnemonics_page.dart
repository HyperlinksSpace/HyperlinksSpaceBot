import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';
import '../wallet/wallet_service.dart';
import '../wallet/wallet_types.dart';
import '../widgets/common/copyable_detail_page.dart';
import 'wallets_page.dart';

class MnemonicsPage extends StatefulWidget {
  const MnemonicsPage({super.key});

  @override
  State<MnemonicsPage> createState() => _MnemonicsPageState();
}

class _MnemonicsPageState extends State<MnemonicsPage> {
  static const String _loadingText = 'Loading...';
  static const String _missingMnemonicText =
      'No mnemonic found on this device.';
  static const String _loadErrorText =
      'Could not load wallet data. Please try again.';
  late final Future<_KeyContent> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _loadKeyContent();
  }

  Future<_KeyContent> _loadKeyContent() async {
    try {
      final service = WalletServiceImpl();
      WalletMaterial? material = await service.getExisting();
      if (material == null && await service.hasWallet()) {
        return _KeyContent.error(_loadErrorText);
      }
      if (material == null) {
        final result = await service.getOrCreate();
        material = result.material;
        final pin = result.pin ?? service.getSessionPin();
        if (material == null) {
          return _KeyContent.error(_missingMnemonicText);
        }
        return _KeyContent(
          _formatMnemonic(material.mnemonicWords),
          pin,
        );
      }
      final pin = service.getSessionPin();
      return _KeyContent(
        _formatMnemonic(material.mnemonicWords),
        pin,
      );
    } catch (_) {
      return _KeyContent.error(_loadErrorText);
    }
  }

  String _formatMnemonic(List<String> words) {
    const wordsPerLine = 4;
    final lines = <String>[];
    for (var i = 0; i < words.length; i += wordsPerLine) {
      final end =
          (i + wordsPerLine < words.length) ? i + wordsPerLine : words.length;
      lines.add(words.sublist(i, end).join(' '));
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_KeyContent>(
      future: _contentFuture,
      builder: (context, snapshot) {
        final content = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final hasError = content?.isError ?? false;
        final mnemonicText = content?.mnemonicText ?? _loadingText;
        final pin = content?.pin;
        final canCopyMnemonic = !loading &&
            snapshot.hasData &&
            !hasError &&
            mnemonicText != _missingMnemonicText;
        final copyText = canCopyMnemonic
            ? (pin != null ? 'PIN: $pin\n\n$mnemonicText' : mnemonicText)
            : '';

        return CopyableDetailPage(
          copyText: copyText,
          onTitleRightTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const WalletsPage(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
            AppHaptic.heavy();
          },
          centerChildBuilder: () {
            final baseColor =
                Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textColor;
            final style = TextStyle(
              fontSize: 15,
              height: 30 / 15,
              fontWeight: FontWeight.w600,
              color: baseColor,
            );
            if (pin != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PIN',
                    style: style.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(pin, style: style.copyWith(letterSpacing: 4)),
                  const SizedBox(height: 20),
                  Text(
                    'Mnemonic',
                    style: style.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mnemonicText,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ],
              );
            }
            return Text(
              mnemonicText,
              textAlign: TextAlign.center,
              style: style,
            );
          },
        );
      },
    );
  }
}

class _KeyContent {
  _KeyContent(this.mnemonicText, this.pin) : isError = false;

  _KeyContent.error(String message)
      : mnemonicText = message,
        pin = null,
        isError = true;

  final String mnemonicText;
  final String? pin;
  final bool isError;
}
