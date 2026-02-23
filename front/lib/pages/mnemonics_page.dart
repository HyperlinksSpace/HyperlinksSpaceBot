import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';
import '../widgets/common/copyable_detail_page.dart';
import 'wallets_page.dart';

class MnemonicsPage extends StatelessWidget {
  const MnemonicsPage({super.key});

  static const String _mnemonicsText =
      'breeze arch just cactus\nfragile author satoshi hurdle\npeace record behind vendor\nacross local exact fatigue\naugust festival indoor movie\nurge garment rule permit';

  @override
  Widget build(BuildContext context) {
    return CopyableDetailPage(
      copyText: _mnemonicsText,
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
          _mnemonicsText,
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
  }
}
