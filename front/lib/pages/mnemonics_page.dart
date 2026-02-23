import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';
import '../wallet/wallet_service.dart';
import '../widgets/common/copyable_detail_page.dart';
import 'wallets_page.dart';

class MnemonicsPage extends StatefulWidget {
  const MnemonicsPage({super.key});

  @override
  State<MnemonicsPage> createState() => _MnemonicsPageState();
}

class _MnemonicsPageState extends State<MnemonicsPage> {
  static const String _missingMnemonicText =
      'No mnemonic found on this device.';
  late final Future<String> _mnemonicTextFuture;

  @override
  void initState() {
    super.initState();
    _mnemonicTextFuture = _loadMnemonicText();
  }

  Future<String> _loadMnemonicText() async {
    try {
      final wallet = await WalletServiceImpl().getExisting();
      if (wallet == null || wallet.mnemonicWords.isEmpty) {
        return _missingMnemonicText;
      }
      return _formatMnemonic(wallet.mnemonicWords);
    } catch (e) {
      return 'Could not load wallet data. Please try again.';
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
    return FutureBuilder<String>(
      future: _mnemonicTextFuture,
      builder: (context, snapshot) {
        final text = snapshot.data ?? 'Loading...';
        return CopyableDetailPage(
          copyText: text,
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
            return Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 30 / 15,
                fontWeight: FontWeight.w600,
                color: baseColor,
              ),
            );
          },
        );
      },
    );
  }
}
