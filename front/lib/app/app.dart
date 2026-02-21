import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../utils/keyboard_height_service.dart';
import '../widgets/global/global_logo_bar.dart';
import '../widgets/global/global_bottom_bar.dart';
import '../widgets/global/ai_search_overlay.dart';
import '../pages/main_page.dart';
import '../screens/bootstrap_screen.dart';
import '../analytics.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Notifier fired when route stack changes (push/pop). Used so overlay can show/hide back button.
  static final ValueNotifier<int> routeStackChangedNotifier = ValueNotifier<int>(0);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize theme from Telegram WebApp
    AppTheme.initialize();
    
    // Initialize keyboard height service (JavaScript-based, no MediaQuery)
    KeyboardHeightService().initialize();
    
    // Initialize Vercel Analytics after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VercelAnalytics.init();
      // Track initial page view
      VercelAnalytics.trackPageView(path: '/', title: 'Home');
      
      // WebApp is already initialized in main() via tma.WebApp().init()
    });
  }
  
  @override
  void dispose() {
    // Clean up listener if needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to theme changes and rebuild when theme changes
    return ValueListenableBuilder<String?>(
      valueListenable: AppTheme.colorSchemeNotifier,
      builder: (context, colorScheme, child) {
        return MaterialApp(
          title: "Hyperlinks.Space App",
          navigatorKey: MyApp.navigatorKey,
          navigatorObservers: [
            MyApp.routeObserver,
            _RouteStackObserver(),
          ],
          builder: (context, child) {
            // Architecture: Independent overlays for top/bottom bars
            // - Top bar (GlobalLogoBar): Positioned at top, can hide/show dynamically
            // - Bottom bar (GlobalBottomBar): Positioned at bottom, moves with keyboard
            // - Main content: Pages handle their own padding using helper methods
            // 
            // KEY FIX: resizeToAvoidBottomInset: false prevents Scaffold from resizing
            // when keyboard opens. This stops page content from rebuilding/reloading.
            // Instead, bottom bar positions itself using MediaQuery.viewInsets.bottom
            // to detect keyboard height and move independently.
            return Scaffold(
              resizeToAvoidBottomInset: false, // CRITICAL: Prevents page reload on keyboard
              backgroundColor: AppTheme.backgroundColor,
              body: Stack(
                clipBehavior: Clip.none, // Allow overlays to extend beyond Stack bounds
                children: [
                  // Main content (pages) - base layer, NEVER rebuilds when keyboard opens
                  // Pages use GlobalLogoBar.getContentTopPadding() for top spacing
                  // Wrap in RepaintBoundary to isolate repaints and prevent visual artifacts
                  // when Stack layout recalculates due to Positioned widget changes
                  RepaintBoundary(
                    child: child ?? const SizedBox.shrink(),
                  ),
                  
                  // Top bar overlay - independent positioning
                  // Hides/shows in Telegram based on fullscreen mode
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: GlobalLogoBar(),
                  ),
                  
                  // Isolated MediaQuery detection widget
                  // This widget rebuilds when keyboard opens/closes, but it's isolated
                  // Only this widget rebuilds, not the Stack or page content
                  // Updates KeyboardHeightService.heightNotifier when keyboard height changes
                  _KeyboardHeightDetector(),
                  
                  // AI search overlay - SAME mechanism as bottom bar: ValueListenableBuilder
                  // directly under Positioned, listening to KeyboardHeightService
                  Positioned(
                    top: GlobalLogoBar.getLogoBlockHeight(),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return ValueListenableBuilder<double>(
                          valueListenable: KeyboardHeightService().heightNotifier,
                          builder: (context, keyboardHeight, child) {
                            final bottomBarHeight =
                                GlobalBottomBar.getBottomBarHeight(null);
                            final contentHeight = (constraints.maxHeight -
                                    keyboardHeight -
                                    bottomBarHeight)
                                .clamp(0.0, constraints.maxHeight);
                            return SizedBox(
                              height: contentHeight,
                              child: child ?? const AiSearchOverlay(),
                            );
                          },
                          child: const AiSearchOverlay(),
                        );
                      },
                    ),
                  ),
                  
                  // Bottom bar overlay - moves with keyboard
                  // Use fixed Positioned with Transform to prevent Stack layout recalculation
                  // This prevents the page slide when keyboard height updates
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ValueListenableBuilder<double>(
                      valueListenable: KeyboardHeightService().heightNotifier,
                      builder: (context, keyboardHeight, child) {
                        // Use Transform.translate instead of changing Positioned.bottom
                        // This prevents Stack from recalculating layout when keyboard height changes
                        return Transform.translate(
                          offset: Offset(0, -keyboardHeight),
                          child: child ?? const GlobalBottomBar(),
                        );
                      },
                      child: const GlobalBottomBar(),
                    ),
                  ),
                ],
              ),
            );
          },
          // Use default theme without Material fonts to avoid loading errors
          theme: ThemeData(
            useMaterial3: false,
            scaffoldBackgroundColor: AppTheme.backgroundColor,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: NoAnimationPageTransitionsBuilder(),
                TargetPlatform.fuchsia: NoAnimationPageTransitionsBuilder(),
              },
            ),
            fontFamily: 'Aeroport',
            textTheme: TextTheme(
              bodyLarge: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              bodyMedium: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              bodySmall: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              displayLarge: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              displayMedium: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              displaySmall: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              headlineLarge: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              headlineMedium: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              headlineSmall: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              titleLarge: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              titleMedium: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              titleSmall: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              labelLarge: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              labelMedium: TextStyle(
                  fontFamily: 'Aeroport',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor),
              labelSmall: TextStyle(
                  fontFamily: 'Aeroport',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.textColor),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(
              fontFamily: 'Aeroport',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.textColor),
          hintStyle: TextStyle(
              fontFamily: 'Aeroport',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.textColor),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(0.0),
          thumbVisibility: WidgetStateProperty.all(false),
          trackVisibility: WidgetStateProperty.all(false),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const BootstrapScreen(home: MainPage()),
        );
      },
    );
  }
}

/// Fires [MyApp.routeStackChangedNotifier] on push/pop so overlay can update back button.
class _RouteStackObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    MyApp.routeStackChangedNotifier.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    MyApp.routeStackChangedNotifier.value++;
  }
}

/// Isolated widget that detects keyboard height using MediaQuery
/// This widget rebuilds when keyboard opens/closes, but it's isolated from Stack
/// Only this widget rebuilds, preventing page content from reloading
/// Works on all platforms: native, browser, and TMA
class _KeyboardHeightDetector extends StatefulWidget {
  const _KeyboardHeightDetector();

  @override
  State<_KeyboardHeightDetector> createState() => _KeyboardHeightDetectorState();
}

class _KeyboardHeightDetectorState extends State<_KeyboardHeightDetector> {
  double _lastHeight = 0.0;

  @override
  Widget build(BuildContext context) {
    // Read MediaQuery - this causes THIS widget to rebuild when keyboard opens/closes
    // But since it's isolated, the Stack doesn't rebuild
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    // Update service notifier when keyboard height changes (2px threshold)
    if ((_lastHeight - keyboardHeight).abs() >= 2.0) {
      final newHeight = keyboardHeight;
      _lastHeight = newHeight;
      // Post-frame to avoid setState during build; both overlay and bottom bar
      // listen to same notifier and will rebuild together
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          KeyboardHeightService().updateHeight(newHeight);
        }
      });
    }
    
    // Return invisible widget - this widget rebuilds but has no visual impact
    return const SizedBox.shrink();
  }
}
