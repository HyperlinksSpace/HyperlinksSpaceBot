import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../app/theme/app_theme.dart';
import '../widgets/global/global_logo_bar.dart';
import '../telegram_safe_area.dart';
import '../telegram_webapp.dart';

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  void _handleBackButton() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
  
  StreamSubscription<tma.BackButton>? _backButtonSubscription;

  // Helper method to calculate adaptive bottom padding
  double _getAdaptiveBottomPadding() {
    final service = TelegramSafeAreaService();
    final safeAreaInset = service.getSafeAreaInset();

    // Formula: bottom SafeAreaInset + 30px
    final bottomPadding = safeAreaInset.bottom + 30;
    return bottomPadding;
  }


  @override
  void initState() {
    super.initState();
    
    // Background animation removed
    
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
    
    // Hide back button when leaving trade page
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
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Builder(
          builder: (context) {
            // Calculate padding statically to avoid rebuilds when keyboard opens
            // The logo visibility doesn't actually change when keyboard opens,
            // so we don't need to listen to fullscreenNotifier here
            return Padding(
              padding: EdgeInsets.only(
                  bottom: _getAdaptiveBottomPadding(),
                  top: GlobalLogoBar.getContentTopPadding()),
              child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.only(
                  top: 30,
                  bottom: 15,
                  left: 15,
                  right: 15,
                ),
                child: Center(
                  child: SvgPicture.asset(
                    AppTheme.isLightTheme
                        ? 'assets/images/404_light.svg'
                        : 'assets/images/404_dark.svg',
                    width: 32,
                    height: 32,
                  ),
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
