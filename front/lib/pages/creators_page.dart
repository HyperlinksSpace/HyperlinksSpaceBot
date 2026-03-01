import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';
import '../telegram_safe_area.dart';
import '../utils/app_haptic.dart';
import '../utils/open_url.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/common/pointer_region.dart';
import '../widgets/global/global_logo_bar.dart';
import 'a_page_example.dart';
import 'wallet_panel_page.dart';

/// Creator's page: header and underlined links (GitHub, Wallet).
/// Back works like other pages (Telegram back button + edge swipe).
class CreatorsPage extends StatelessWidget {
  const CreatorsPage({super.key});

  static const String _githubUrl = 'https://github.com/HyperlinksSpace/HyperlinksSpaceBot';

  double _getAdaptiveBottomPadding() {
    final safeAreaInset = TelegramSafeAreaService().getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  void _openLink(String url) {
    AppHaptic.heavy();
    openInNewTab(url);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    final bottomPadding = _getAdaptiveBottomPadding();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: EdgeSwipeBack(
        onBack: () {
          AppHaptic.heavy();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(15, 30, 15, 30),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (topPadding == 0.0)
                            const SizedBox(height: 10),
                          Text(
                            "A Creator's Page",
                            style: TextStyle(
                              fontFamily: 'Aeroport',
                              fontSize: 30,
                              height: 1.0,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.textColor,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _LinkTile(
                            label: 'GitHub',
                            onTap: () => _openLink(_githubUrl),
                          ),
                          const SizedBox(height: 16),
                          _LinkTile(
                            label: 'A Page Example',
                            onTap: () {
                              AppHaptic.heavy();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const APageExample(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _LinkTile(
                            label: 'Wallet Panel',
                            onTap: () {
                              AppHaptic.heavy();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const WalletPanelPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Aeroport',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: AppTheme.textColor,
          height: 1.0,
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.textColor,
        ),
      ),
    ).pointer;
  }
}
