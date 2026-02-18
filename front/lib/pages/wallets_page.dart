import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../widgets/global/global_logo_bar.dart';
import '../widgets/common/edge_swipe_back.dart';
import '../widgets/common/wallet_panel.dart';
import '../services/wallet/mock_wallet_service.dart';
import '../services/wallet/wallet_service.dart';
import '../telegram_safe_area.dart';
import '../app/theme/app_theme.dart';
import '../telegram_webapp.dart';
import '../utils/app_haptic.dart';

class WalletsPage extends StatefulWidget {
  const WalletsPage({super.key});

  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  static const bool kUseMockWalletState = true;

  late final WalletService _walletService;
  MockWalletService? _mockWalletService;
  WalletMockScenario _mockScenario = WalletMockScenario.deploying;

  String _stateLabel(WalletMockScenario state) {
    switch (state) {
      case WalletMockScenario.noWallet:
        return 'No wallet';
      case WalletMockScenario.generating:
        return 'Generating';
      case WalletMockScenario.deploying:
        return 'Deploying';
      case WalletMockScenario.ready:
        return 'Ready';
      case WalletMockScenario.restored:
        return 'Restored';
    }
  }

  void _handleBackButton() {
    AppHaptic.heavy();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  
  StreamSubscription<tma.BackButton>? _backButtonSubscription;
  // Helper method to calculate adaptive bottom padding
  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }

  @override
  void initState() {
    super.initState();

    _walletService =
        kUseMockWalletState ? MockWalletService() : RealWalletService();
    if (_walletService is MockWalletService) {
      _mockWalletService = _walletService as MockWalletService;
      _mockWalletService!.setScenario(_mockScenario);
    }
    
    // Set up back button using flutter_telegram_miniapp package
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final webApp = tma.WebApp();
        final eventHandler = webApp.eventHandler;
        
        // IMPORTANT: Register listener BEFORE showing the button
        // Listen to backButtonClicked event
        _backButtonSubscription = eventHandler.backButtonClicked.listen((backButton) {
          print('[SwapPage] Back button clicked!');
          _handleBackButton();
        });
        
        print('[SwapPage] Back button listener registered');
        
        // Also set up fallback using direct TelegramWebApp API
        try {
          final telegramWebApp = TelegramWebApp();
          telegramWebApp.onBackButtonClick(() {
            print('[SwapPage] Back button clicked (fallback)!');
            _handleBackButton();
          });
          print('[SwapPage] Fallback back button listener registered');
        } catch (e) {
          print('[SwapPage] Error setting up fallback back button: $e');
        }
        
        // Show the back button after a short delay to ensure listener is ready
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            if (mounted) {
              webApp.backButton.show();
              print('[SwapPage] Back button shown');
            }
          } catch (e) {
            print('[SwapPage] Error showing back button: $e');
          }
        });
      } catch (e) {
        print('[SwapPage] Error setting up back button: $e');
      }
    });
  }

  @override
  void dispose() {
    _backButtonSubscription?.cancel();
    
    // Hide back button when leaving wallets page
    try {
      tma.WebApp().backButton.hide();
    } catch (e) {
      // Ignore errors
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: EdgeSwipeBack(
        onBack: _handleBackButton,
        child: Builder(
          builder: (context) {
            // Calculate padding statically to avoid rebuilds when keyboard opens
            // The logo visibility doesn't actually change when keyboard opens,
            // so we don't need to listen to fullscreenNotifier here
            final topPadding = GlobalLogoBar.getContentTopPadding();
            return Padding(
              padding: EdgeInsets.only(
                bottom: _getAdaptiveBottomPadding(),
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
                      children: [
                      WalletPanel(
                        walletService: _walletService,
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: WalletMockScenario.values.map((state) {
                            final selected = _mockScenario == state;
                            final label = _stateLabel(state);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _mockScenario = state;
                                  _mockWalletService?.setScenario(state);
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: selected
                                        ? AppTheme.buttonBackgroundColor
                                        : (AppTheme.isLightTheme
                                            ? const Color(0xFFF1F1F1)
                                            : const Color(0xFF222222)),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 12,
                                      color: selected
                                          ? AppTheme.buttonTextColor
                                          : const Color(0xFF818181),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Placeholder only; integration will replace mock state.
                      // TODO: wire to WalletService (front-only local service or backend provider)
                      // pending architecture decision.
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 20,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '1 wallet',
                            style: TextStyle(
                              fontFamily: 'Aeroport',
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF818181),
                              height: 20,
                            ),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 30,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            r'$1',
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
                            // Wallet name and address column (left-aligned)
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
                            // Amount, icon, and currency column (right-aligned)
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
                                          r'$1',
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
                                        SvgPicture.asset('assets/icons/select.svg', width: 5, height: 10),
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
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        ),
    );
  }
}
