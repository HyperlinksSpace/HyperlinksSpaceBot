import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../widgets/global/global_bottom_bar.dart';
import '../../widgets/global/global_logo_bar.dart';
import '../../utils/telegram_back_button.dart';
import '../../telegram_webapp.dart';

/// Overlay widget that appears when AI & Search input is focused
/// Shows premade input options and overlays page content
class AiSearchOverlay extends StatefulWidget {
  const AiSearchOverlay({super.key});

  @override
  State<AiSearchOverlay> createState() => _AiSearchOverlayState();
}

class _AiSearchOverlayState extends State<AiSearchOverlay> {
  // Premade input options
  final List<String> _premadeOptions = [
    "What is my all wallet's last month profit",
    "Advise me a token to buy",
  ];

  // Store the callback reference for cleanup
  Function()? _backButtonCallback;

  @override
  void initState() {
    super.initState();
    // Setup Telegram back button handler when overlay appears
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupBackButton();
    });
  }

  void _setupBackButton() {
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram) {
      // Create callback to unfocus input when back button is clicked
      _backButtonCallback = () {
        GlobalBottomBar.unfocusInput();
      };
      
      // Show back button and handle clicks
      TelegramBackButton.show();
      TelegramBackButton.onClick(_backButtonCallback!);
    }
  }

  @override
  void dispose() {
    // Hide back button and remove callback when overlay is removed
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram && _backButtonCallback != null) {
      TelegramBackButton.offClick(_backButtonCallback!);
      TelegramBackButton.hide();
    }
    super.dispose();
  }

  void _onOptionTap(String option) {
    // Set the option text to the input field
    GlobalBottomBar.setInputText(option);
    // Keep focus so user can edit if needed
    // Don't unfocus here - let user decide when to submit
  }

  void _onCloseTap() {
    GlobalBottomBar.unfocusInput();
  }

  void _onOverlayTap() {
    // Close overlay when tapping outside options
    GlobalBottomBar.unfocusInput();
  }

  @override
  Widget build(BuildContext context) {
    final logoBarHeight = GlobalLogoBar.getLogoBlockHeight();
    final bottomBarHeight = 60.0; // Approximate height of bottom bar
    final telegramWebApp = TelegramWebApp();
    final isInTelegram = telegramWebApp.isActuallyInTelegram;

    return Positioned(
      top: logoBarHeight,
      left: 0,
      right: 0,
      bottom: bottomBarHeight,
      child: GestureDetector(
        onTap: _onOverlayTap,
        behavior: HitTestBehavior.translucent,
        child: Material(
          color: AppTheme.backgroundColor,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: AppTheme.backgroundColor,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Stack(
                children: [
                  // Close button in top-left (only in Telegram)
                  if (isInTelegram)
                    Positioned(
                      top: 15,
                      left: 15,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: GestureDetector(
                            onTap: _onCloseTap,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.isLightTheme
                                    ? Colors.grey[200]
                                    : Colors.grey[800],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close,
                                    size: 16,
                                    color: AppTheme.textColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Close',
                                    style: TextStyle(
                                      fontFamily: 'Aeroport',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Premade input options centered
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: GestureDetector(
                          onTap: () {}, // Prevent tap from propagating to overlay
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Premade input options
                              ..._premadeOptions.map((option) => Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: GestureDetector(
                                      onTap: () => _onOptionTap(option),
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        option,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontFamily: 'Aeroport',
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textColor,
                                        ),
                                      ),
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
