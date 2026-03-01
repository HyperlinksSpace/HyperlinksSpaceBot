import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/global/global_logo_bar.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../telegram_safe_area.dart';
import '../app/theme/app_theme.dart';
import '../utils/app_haptic.dart';

/// Wallets page: logo bar, bottom bar, scrolling, back, and wallet list (1 wallet, balance, Sendal Rodriges row).
/// Wallet panel (status card + state selector) is only on [WalletPanelPage].
class WalletsPage extends StatelessWidget {
  const WalletsPage({super.key});

  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();
    return safeAreaInset.bottom + 30;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = GlobalLogoBar.getContentTopPadding();
    // Match MainPage: add a small internal gap when TMA is not fullscreen.
    final needsScrollableTopGap = topPadding == 0.0;
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
          padding: EdgeInsets.only(
            bottom: bottomPadding,
            top: topPadding,
            left: 15,
            right: 15,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 570),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needsScrollableTopGap)
                      const SizedBox(height: 10),
                    SizedBox(
                      height: 30,
                      child: Center(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '2 wallets',
                            style: const TextStyle(
                              fontFamily: 'Aeroport',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF818181),
                              height: 2.0,
                            ),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      height: 30,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          r'3$',
                          style: TextStyle(
                            fontFamily: 'Aeroport',
                            fontSize: 30,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.textColor,
                            height: 30,
                          ),
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Sendal Rodriges',
                                      style: TextStyle(
                                        fontFamily: 'Aeroport',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textColor,
                                        height: 20 / 15,
                                      ),
                                      textHeightBehavior: const TextHeightBehavior(
                                        applyHeightToFirstAscent: false,
                                        applyHeightToLastDescent: false,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '..xk5str4e',
                                      style: const TextStyle(
                                        fontFamily: 'Aeroport Mono',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF818181),
                                        height: 20 / 15,
                                      ),
                                      textHeightBehavior: const TextHeightBehavior(
                                        applyHeightToFirstAscent: false,
                                        applyHeightToLastDescent: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 20,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        r'1$',
                                        style: TextStyle(
                                          fontFamily: 'Aeroport',
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textColor,
                                          height: 20 / 15,
                                        ),
                                        textAlign: TextAlign.right,
                                        textHeightBehavior: const TextHeightBehavior(
                                          applyHeightToFirstAscent: false,
                                          applyHeightToLastDescent: false,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      SvgPicture.asset(
                                          'assets/icons/select.svg',
                                          width: 5,
                                          height: 10),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              SizedBox(
                                height: 20,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'TON',
                                    style: const TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 20 / 15,
                                    ),
                                    textAlign: TextAlign.right,
                                    textHeightBehavior: const TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Wallet 2',
                                      style: TextStyle(
                                        fontFamily: 'Aeroport',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textColor,
                                        height: 20 / 15,
                                      ),
                                      textHeightBehavior: const TextHeightBehavior(
                                        applyHeightToFirstAscent: false,
                                        applyHeightToLastDescent: false,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                SizedBox(
                                  height: 20,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '..x53n79i3',
                                      style: const TextStyle(
                                        fontFamily: 'Aeroport Mono',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w400,
                                        color: Color(0xFF818181),
                                        height: 20 / 15,
                                      ),
                                      textHeightBehavior: const TextHeightBehavior(
                                        applyHeightToFirstAscent: false,
                                        applyHeightToLastDescent: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SizedBox(
                                height: 20,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        r'2$',
                                        style: TextStyle(
                                          fontFamily: 'Aeroport',
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textColor,
                                          height: 20 / 15,
                                        ),
                                        textAlign: TextAlign.right,
                                        textHeightBehavior: const TextHeightBehavior(
                                          applyHeightToFirstAscent: false,
                                          applyHeightToLastDescent: false,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      SvgPicture.asset(
                                          'assets/icons/select.svg',
                                          width: 5,
                                          height: 10),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              SizedBox(
                                height: 20,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'ETH',
                                    style: const TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF818181),
                                      height: 20 / 15,
                                    ),
                                    textAlign: TextAlign.right,
                                    textHeightBehavior: const TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
