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
  bool _isFocused = false;
  bool _backButtonSetup = false;
  
  // Cache heights to prevent recalculation when MediaQuery changes (keyboard opens)
  double? _cachedLogoBarHeight;
  double? _cachedBottomBarHeight;
  
  @override
  void initState() {
    super.initState();
    // Track initial focus state
    _isFocused = GlobalBottomBar.focusNotifier.value;
    // Listen to focus changes to update state and setup/teardown back button
    GlobalBottomBar.focusNotifier.addListener(_onFocusChanged);
    
    // Cache heights immediately in post-frame callback to ensure they're set before first build
    // This prevents recalculation when MediaQuery changes (keyboard opens)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cacheHeightsFromContext();
      }
    });
  }
  
  void _cacheHeightsFromContext() {
    // Cache heights only once to prevent recalculation when MediaQuery changes
    if (_cachedLogoBarHeight == null) {
      _cachedLogoBarHeight = GlobalLogoBar.shouldShowLogo()
          ? GlobalLogoBar.getLogoBlockHeight()
          : 0.0;
    }
    // Note: We can't cache bottomBarHeight here without context, so it will be cached on first build
  }
  
  void _cacheHeights(BuildContext context) {
    // Cache heights only once to prevent recalculation when MediaQuery changes
    if (_cachedLogoBarHeight == null) {
      _cachedLogoBarHeight = GlobalLogoBar.shouldShowLogo()
          ? GlobalLogoBar.getLogoBlockHeight()
          : 0.0;
    }
    if (_cachedBottomBarHeight == null) {
      // Cache bottom bar height - this should be stable regardless of keyboard state
      // getBottomBarHeight only reads padding.bottom, not viewInsets.bottom
      _cachedBottomBarHeight = GlobalBottomBar.getBottomBarHeight(context);
    }
  }

  void _onFocusChanged() {
    final newFocusState = GlobalBottomBar.focusNotifier.value;
    
    // Only react to actual changes
    if (newFocusState == _isFocused) return;
    
    setState(() {
      _isFocused = newFocusState;
    });
    
    if (_isFocused) {
      // TEMPORARILY DISABLED: Delay back button setup to test if it causes reload
      // TODO: Re-enable after confirming this is not the cause of reload
      // Future.delayed(const Duration(milliseconds: 500), () {
      //   if (mounted && GlobalBottomBar.focusNotifier.value && !_backButtonSetup) {
      //     _setupBackButton();
      //   }
      // });
    } else {
      _teardownBackButton();
    }
  }

  void _setupBackButton() {
    if (_backButtonSetup) return; // Prevent multiple setups
    
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram) {
      // Create callback to unfocus input when back button is clicked
      _backButtonCallback = () {
        GlobalBottomBar.unfocusInput();
      };
      
      // Show back button and handle clicks
      // Use postFrameCallback to ensure this happens after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GlobalBottomBar.focusNotifier.value && !_backButtonSetup) {
          try {
            TelegramBackButton.show();
            TelegramBackButton.onClick(_backButtonCallback!);
            _backButtonSetup = true;
          } catch (e) {
            // Silently fail if back button setup fails
            print('Failed to setup back button: $e');
          }
        }
      });
    }
  }

  void _teardownBackButton() {
    if (!_backButtonSetup) return; // Nothing to teardown
    
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram && _backButtonCallback != null) {
      try {
        TelegramBackButton.offClick(_backButtonCallback!);
        TelegramBackButton.hide();
      } catch (e) {
        // Silently fail if back button teardown fails
        print('Failed to teardown back button: $e');
      }
      _backButtonCallback = null;
      _backButtonSetup = false;
    }
  }

  @override
  void dispose() {
    GlobalBottomBar.focusNotifier.removeListener(_onFocusChanged);
    // Clean up back button if still active
    _teardownBackButton();
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
    // Cache heights on first build to prevent recalculation when MediaQuery changes
    _cacheHeights(context);
    
    // Use cached heights to prevent layout shifts when keyboard opens
    // These values are calculated once and remain stable
    final logoBarHeight = _cachedLogoBarHeight ?? 0.0;
    final bottomBarHeight = _cachedBottomBarHeight ?? GlobalBottomBar.getBottomBarHeight(context);

    // Always render the same widget structure to prevent tree changes
    // Use Offstage to keep widget in tree but not render when not focused
    return Positioned(
      top: logoBarHeight,
      left: 0,
      right: 0,
      bottom: bottomBarHeight,
      child: Offstage(
        offstage: !_isFocused,
        child: IgnorePointer(
          ignoring: !_isFocused,
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
                      // Premade input options centered - always in tree
                      Center(
                        child: Offstage(
                          offstage: !_isFocused,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 15),
                              child: GestureDetector(
                                onTap: () {},
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Premade input options
                                    ..._premadeOptions.map((option) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 20),
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
