import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import '../../app/theme/app_theme.dart';
import '../../telegram_safe_area.dart';
import '../../telegram_webapp.dart';

class GlobalLogoBar extends StatefulWidget {
  const GlobalLogoBar({super.key});

  @override
  State<GlobalLogoBar> createState() => _GlobalLogoBarState();

  // Notifier for fullscreen status changes (to trigger content rebuilds)
  static final ValueNotifier<bool> _fullscreenNotifier = ValueNotifier<bool>(true);
  static ValueNotifier<bool> get fullscreenNotifier => _fullscreenNotifier;

  // Helper method to calculate logo top padding
  static double _getLogoTopPadding() {
    final service = TelegramSafeAreaService();
    
    // Check if we're in a browser (Telegram WebApp not available)
    // In browser, safe area insets are not available, so use fallback
    if (!service.isAvailable) {
      // Browser fallback: use 30px top padding
      return 30.0;
    }
    
    final safeAreaInset = service.getSafeAreaInset();
    final contentSafeAreaInset = service.getContentSafeAreaInset();

    // If both insets are zero (browser or no safe area data), use fallback
    if (safeAreaInset.isEmpty && contentSafeAreaInset.isEmpty) {
      // Browser fallback: use 30px top padding
      return 30.0;
    }

    // Formula: top SafeAreaInset + (top ContentSafeAreaInset / 2) - 16
    // This centers the 32px logo in the content safe area zone, respecting the upper inset
    final topPadding = safeAreaInset.top + (contentSafeAreaInset.top / 2) - 16;
    return topPadding;
  }

  // Helper method to calculate logo block height
  // Logo block consists of: top padding + logo (32px) + bottom padding (10px)
  static double getLogoBlockHeight() {
    const logoHeight = 32.0;
    const bottomPadding = 10.0;
    
    return _getLogoTopPadding() + logoHeight + bottomPadding;
  }

  /// Get the top padding for content based on logo visibility
  /// Returns 10px when logo is hidden, otherwise logo block height + 10px
  /// Uses the fullscreenNotifier to get current logo visibility state
  static double getContentTopPadding() {
    // Check if we're in browser or TMA
    final telegramWebApp = TelegramWebApp();
    final isInBrowser = !telegramWebApp.isActuallyInTelegram;
    
    // Debug logging
    print('[GlobalLogoBar] getContentTopPadding - isAvailable: ${telegramWebApp.isAvailable}, isActuallyInTelegram: ${telegramWebApp.isActuallyInTelegram}, platform: ${telegramWebApp.platform}, initData: ${telegramWebApp.initData}');
    
    // In browser mode, logo is always visible, so content needs full padding
    if (isInBrowser) {
      final logoBlockHeight = getLogoBlockHeight();
      final padding = logoBlockHeight + 10.0;
      print('[GlobalLogoBar] Browser mode - content top padding: $padding (logoBlockHeight: $logoBlockHeight)');
      return padding;
    }
    
    // In TMA mode, check if logo is visible (fullscreen mode)
    // If logo is hidden (not fullscreen), return minimal padding
    final isFullscreen = _fullscreenNotifier.value;
    if (!isFullscreen) {
      print('[GlobalLogoBar] TMA not fullscreen - content top padding: 10.0');
      return 10.0;
    }
    
    // Logo is visible in TMA fullscreen mode, so content needs full padding
    final logoBlockHeight = getLogoBlockHeight();
    final padding = logoBlockHeight + 10.0;
    print('[GlobalLogoBar] TMA fullscreen - content top padding: $padding (logoBlockHeight: $logoBlockHeight)');
    return padding;
  }

  /// Check if logo should be visible
  /// Logo is hidden when: in Telegram AND not in fullscreen
  /// In browser (not Telegram): always show logo
  static bool shouldShowLogo() {
    final telegramWebApp = TelegramWebApp();
    
    // If not in Telegram (browser), always show logo
    if (!telegramWebApp.isActuallyInTelegram) {
      return true; // Always show in browser
    }
    
    // We're in Telegram - check isFullscreen
    final isFullscreen = telegramWebApp.isFullscreen;
    
    // If isFullscreen is null or true, show logo (safe fallback to show)
    // Only hide logo when explicitly not fullscreen (isFullscreen == false)
    return isFullscreen ?? true;
  }
}

class _GlobalLogoBarState extends State<GlobalLogoBar> with SingleTickerProviderStateMixin {
  Timer? _viewportDebounceTimer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller (kept for potential future use)
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Show logo by default, then check after 1 second
    GlobalLogoBar._fullscreenNotifier.value = true;
    _animationController.value = 1.0; // Start at full scale (visible)
    
    // Check immediately if in browser (don't wait 1 second)
    final telegramWebApp = TelegramWebApp();
    if (!telegramWebApp.isActuallyInTelegram) {
      // In browser, ensure logo is visible and notifier is set immediately
      GlobalLogoBar._fullscreenNotifier.value = true;
    } else {
      // In TMA, check fullscreen status immediately
      final isFullscreen = telegramWebApp.isFullscreen;
      final shouldShow = isFullscreen ?? true;
      GlobalLogoBar._fullscreenNotifier.value = shouldShow;
      
      // Removed 1-second timer check - it was causing unnecessary rebuilds
      // The viewport listener will handle real fullscreen status changes
    }
    
    _setupViewportListener();
  }

  @override
  void dispose() {
    _viewportDebounceTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _updateFullscreenStatus() {
    final telegramWebApp = TelegramWebApp();
    if (!telegramWebApp.isActuallyInTelegram) {
      // Only update if value actually changed
      if (GlobalLogoBar._fullscreenNotifier.value != true) {
        GlobalLogoBar._fullscreenNotifier.value = true;
      }
      return;
    }
    
    // Update fullscreen notifier directly based on isFullscreen
    final isFullscreen = telegramWebApp.isFullscreen;
    final shouldShow = isFullscreen ?? true;
    
    // Only update notifier and rebuild if value actually changed
    // This prevents unnecessary rebuilds when viewport changes due to keyboard
    if (GlobalLogoBar._fullscreenNotifier.value != shouldShow) {
      GlobalLogoBar._fullscreenNotifier.value = shouldShow;
      
      if (mounted) {
        setState(() {}); // Force rebuild only when value actually changed
      }
    }
  }

  void _setupViewportListener() {
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram) {
      telegramWebApp.onViewportChanged((data) {
        // Debounce viewport changes to prevent rapid-fire updates
        // This is especially important when keyboard opens/closes
        _viewportDebounceTimer?.cancel();
        _viewportDebounceTimer = Timer(const Duration(milliseconds: 300), () {
          _updateFullscreenStatus();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppTheme.colorSchemeNotifier,
      builder: (context, colorScheme, _) {
        // Check if we're in browser or TMA
        final telegramWebApp = TelegramWebApp();
        final isInBrowser = !telegramWebApp.isActuallyInTelegram;
        
        // In browser mode, always show logo without animation
        if (isInBrowser) {
          final logoBlockHeight = GlobalLogoBar.getLogoBlockHeight();
          return Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  height: logoBlockHeight,
                  padding: EdgeInsets.only(
                      top: GlobalLogoBar._getLogoTopPadding(),
                      bottom: 10,
                      left: 15,
                      right: 15),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: SvgPicture.asset(
                          AppTheme.isLightTheme
                              ? 'assets/images/logo_light.svg'
                              : 'assets/images/logo_dark.svg',
                          width: 32,
                          height: 32,
                          key: const ValueKey('global_logo'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        
        // In TMA mode, check isFullscreen and show/hide logo directly without animation
        // Use ValueListenableBuilder to react to fullscreen changes
        return ValueListenableBuilder<bool>(
          valueListenable: GlobalLogoBar.fullscreenNotifier,
          builder: (context, shouldShowLogo, _) {
            // Hide logo if not fullscreen
            if (!shouldShowLogo) {
              return const SizedBox.shrink();
            }
            
            // Show logo directly in TMA fullscreen mode
            final logoBlockHeight = GlobalLogoBar.getLogoBlockHeight();
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    height: logoBlockHeight,
                    padding: EdgeInsets.only(
                        top: GlobalLogoBar._getLogoTopPadding(),
                        bottom: 10,
                        left: 15,
                        right: 15),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: SvgPicture.asset(
                            AppTheme.isLightTheme
                                ? 'assets/images/logo_light.svg'
                                : 'assets/images/logo_dark.svg',
                            width: 32,
                            height: 32,
                            key: const ValueKey('global_logo'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

