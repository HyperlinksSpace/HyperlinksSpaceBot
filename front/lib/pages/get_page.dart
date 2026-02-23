import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';
import '../widgets/common/copyable_detail_page.dart';
import 'wallets_page.dart';

class GetPage extends StatelessWidget {
  const GetPage({super.key});

  static const String _addressText =
      'EQCNT_JdH8Vc\n-kJyr_-HhBge\n7JpMMiR8X8yn\nsUJalr_qRiKE';

  @override
  Widget build(BuildContext context) {
    return CopyableDetailPage(
      copyText: _addressText,
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
        final baseColor = Theme.of(context).textTheme.bodyLarge?.color ?? AppTheme.textColor;
        return Text(
          _addressText,
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
  }
}
