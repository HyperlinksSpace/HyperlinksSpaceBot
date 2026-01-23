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
  
  // Track if keyboard has been opened (to show options after layout stabilizes)
  bool _keyboardOpened = false;

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

  void _onOverlayTap() {
    // Close overlay when tapping outside options
    GlobalBottomBar.unfocusInput();
  }

  @override
  Widget build(BuildContext context) {
    final logoBarHeight = GlobalLogoBar.getLogoBlockHeight();
    // Get actual bottom bar height including padding and SafeArea
    final bottomBarHeight = GlobalBottomBar.getBottomBarHeight(context);
    
    // Get keyboard height from MediaQuery viewInsets
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    
    // Show options when input is focused (check focus state directly)
    final isFocused = GlobalBottomBar.focusNotifier.value;
    
    // Update keyboard state when keyboard opens/closes
    if (keyboardHeight > 10) {
      if (!_keyboardOpened) {
        // Use a small delay to ensure layout is stable before showing options
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && MediaQuery.of(context).viewInsets.bottom > 10) {
            setState(() {
              _keyboardOpened = true;
            });
          }
        });
      }
    } else {
      if (_keyboardOpened) {
        // Reset when keyboard closes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _keyboardOpened = false;
            });
          }
        });
      }
    }
    
    // Show options immediately when focused, regardless of keyboard state
    final shouldShowOptions = isFocused;

    return Positioned(
      top: logoBarHeight,
      left: 0,
      right: 0,
      bottom: bottomBarHeight + keyboardHeight,
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
                  // Premade input options centered (only shown after keyboard opens)
                  if (shouldShowOptions)
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
