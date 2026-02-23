import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';
import '../wallet/wallet_service.dart';
import '../widgets/common/copyable_detail_page.dart';
import 'wallets_page.dart';

class GetPage extends StatefulWidget {
  const GetPage({super.key});

  @override
  State<GetPage> createState() => _GetPageState();
}

class _GetPageState extends State<GetPage> {
  static const String _loadingText = 'Loading...';
  static const String _missingAddressText =
      'Wallet public key (hex) not found on this device.';
  static const String _loadErrorText =
      'Could not load wallet data. Please try again.';
  late final Future<String> _addressTextFuture;

  @override
  void initState() {
    super.initState();
    _addressTextFuture = _loadAddressText();
  }

  Future<String> _loadAddressText() async {
    try {
      final wallet = await WalletServiceImpl().getExisting();
      if (wallet == null || wallet.publicKeyHex.trim().isEmpty) {
        return _missingAddressText;
      }
      return _formatForDisplay(
          'Wallet public key (hex)\n${wallet.publicKeyHex}');
    } catch (_) {
      return _loadErrorText;
    }
  }

  String _formatForDisplay(String value) {
    const chunkSize = 12;
    final chunks = <String>[];
    for (var i = 0; i < value.length; i += chunkSize) {
      final end =
          (i + chunkSize < value.length) ? i + chunkSize : value.length;
      chunks.add(value.substring(i, end));
    }
    return chunks.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _addressTextFuture,
      builder: (context, snapshot) {
        final String text = snapshot.data ?? _loadingText;
        final bool canCopyText =
            snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                text != _missingAddressText &&
                text != _loadErrorText;
        return CopyableDetailPage(
          copyText: canCopyText ? text : '',
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
                fontSize: 30,
                height: 55 / 30,
                fontWeight: FontWeight.w500,
                color: baseColor,
              ),
            );
          },
        );
      },
    );
  }
}
