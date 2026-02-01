import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import '../app/theme/app_theme.dart';
import '../widgets/global/global_logo_bar.dart';
import '../telegram_safe_area.dart';
import '../telegram_webapp.dart';

class _TradeColumn extends StatelessWidget {
  const _TradeColumn({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  final String imagePath;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: AspectRatio(
            aspectRatio: 1,
            child: SvgPicture.asset(
              imagePath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF818181),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

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
      body: Builder(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // First block: 2 columns with pictures, titles, subtitles
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TradeColumn(
                            imagePath: 'assets/sample/pixakats.svg',
                            title: 'pixa kats',
                            subtitle: 'Tandam',
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _TradeColumn(
                            imagePath: 'assets/sample/Haramarta.svg',
                            title: 'Haramarta',
                            subtitle: 'Bid Raits',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // Second block: three 11×11 squares (centered)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 11,
                            height: 11,
                            color: AppTheme.textColor,
                          ),
                        const SizedBox(width: 11),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF818181),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF818181),
                              width: 1,
                            ),
                          ),
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
    );
  }
}
