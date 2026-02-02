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

  // Cache initial safe area values to prevent recalculation when keyboard opens
  // These values are set once during initialization and don't change during keyboard operations
  static double? _cachedLogoTopPadding;
  static double? _cachedLogoBlockHeight;
  static bool _hasCachedValues = false;

  // Helper method to calculate logo top padding
  // CRITICAL: Caches the value to prevent recalculation when keyboard opens
  // Safe area values should not change during keyboard operations
  static double _getLogoTopPadding() {
    // Return cached value if available to prevent recalculation during keyboard operations
    if (_hasCachedValues && _cachedLogoTopPadding != null) {
      return _cachedLogoTopPadding!;
    }
    
    final service = TelegramSafeAreaService();
    
    // Check if we're in a browser (Telegram WebApp not available)
    // In browser, safe area insets are not available, so use fallback
    if (!service.isAvailable) {
      // Browser fallback: use 30px top padding
      _cachedLogoTopPadding = 30.0;
      _hasCachedValues = true;
      return 30.0;
    }
    
    final safeAreaInset = service.getSafeAreaInset();
    final contentSafeAreaInset = service.getContentSafeAreaInset();

    // If both insets are zero (browser or no safe area data), use fallback
    if (safeAreaInset.isEmpty && contentSafeAreaInset.isEmpty) {
      // Browser fallback: use 30px top padding
      _cachedLogoTopPadding = 30.0;
      _hasCachedValues = true;
      return 30.0;
    }

    // Formula: top SafeAreaInset + (top ContentSafeAreaInset / 2) - 16
    // This centers the 32px logo in the content safe area zone, respecting the upper inset
    final topPadding = safeAreaInset.top + (contentSafeAreaInset.top / 2) - 16;
    
    // Cache the value to prevent recalculation when keyboard opens
    _cachedLogoTopPadding = topPadding;
    _hasCachedValues = true;
    
    return topPadding;
  }

  // Helper method to calculate logo block height
  // Logo block consists of: top padding + logo (32px) + bottom padding (10px)
  // CRITICAL: Caches the value to prevent recalculation when keyboard opens
  static double getLogoBlockHeight() {
    // Return cached value if available to prevent recalculation during keyboard operations
    if (_hasCachedValues && _cachedLogoBlockHeight != null) {
      return _cachedLogoBlockHeight!;
    }
    
    const logoHeight = 32.0;
    const bottomPadding = 10.0;
    
    final height = _getLogoTopPadding() + logoHeight + bottomPadding;
    
    // Cache the value to prevent recalculation when keyboard opens
    _cachedLogoBlockHeight = height;
    
    return height;
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
    
    // CRITICAL: Initialize cached safe area values ONCE during init
    // This prevents recalculation when keyboard opens and viewport changes
    // The cache is initialized on first access, but we ensure it's set here
    if (!GlobalLogoBar._hasCachedValues) {
      // Force calculation and caching of logo padding values
      GlobalLogoBar._getLogoTopPadding();
      GlobalLogoBar.getLogoBlockHeight();
      print('[GlobalLogoBar] Cached initial safe area values for logo positioning');
    }
    
    // Determine initial logo visibility
    final telegramWebApp = TelegramWebApp();
    
    if (!telegramWebApp.isActuallyInTelegram) {
      // In browser: Always show logo
      GlobalLogoBar._fullscreenNotifier.value = true;
      _animationController.value = 1.0;
    } else {
      // In TMA: Check initial fullscreen status
      final isFullscreen = telegramWebApp.isFullscreen;
      final shouldShow = isFullscreen ?? true; // Default to true if null
      GlobalLogoBar._fullscreenNotifier.value = shouldShow;
      _animationController.value = shouldShow ? 1.0 : 0.0;
      
      print('[GlobalLogoBar] Initial state: isFullscreen=$isFullscreen, shouldShow=$shouldShow');
    }
    
    // Viewport listener disabled - logo visibility is now static during keyboard operations
    // See _setupViewportListener() for details
    _setupViewportListener();
  }

  @override
  void dispose() {
    _viewportDebounceTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _setupViewportListener() {
    // DISABLED: Viewport listener was causing logo to hide when keyboard opens
    // because Telegram reports isFullscreen=false when viewport shrinks (keyboard opening).
    // This is NOT the same as user pulling down the mini app to exit fullscreen.
    // 
    // With the new overlay architecture (Stack + Positioned), we don't need to
    // react to viewport changes. Logo visibility is determined once at init based
    // on initial fullscreen state, and stays fixed during keyboard operations.
    //
    // If needed in the future, we could distinguish between:
    // - Keyboard viewport changes (viewportHeight < viewportStableHeight)
    // - User fullscreen exit (actual isFullscreen property change)
    
    // final telegramWebApp = TelegramWebApp();
    // if (telegramWebApp.isActuallyInTelegram) {
    //   telegramWebApp.onViewportChanged((data) {
    //     _viewportDebounceTimer?.cancel();
    //     _viewportDebounceTimer = Timer(const Duration(milliseconds: 300), () {
    //       _updateFullscreenStatus();
    //     });
    //   });
    // }
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
          // Don't use SafeArea - it reads MediaQuery and causes rebuilds
          // Safe area calculations are handled via TelegramSafeAreaService in _getLogoTopPadding()
          return Material(
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
                      'assets/images/loga.svg',
                      width: 32,
                      height: 32,
                      key: const ValueKey('global_logo'),
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
            // Don't use SafeArea - it reads MediaQuery and causes rebuilds
            // Safe area calculations are handled via TelegramSafeAreaService in _getLogoTopPadding()
            return Material(
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
                        'assets/images/loga.svg',
                        width: 32,
                        height: 32,
                        key: const ValueKey('global_logo'),
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

