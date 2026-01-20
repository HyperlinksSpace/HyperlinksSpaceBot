import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import '../utils/page_transitions.dart';
import '../widgets/global/global_logo_bar.dart';
import '../widgets/global/global_bottom_bar.dart';
import '../widgets/global/ai_search_overlay.dart';
import '../pages/main_page.dart';
import '../analytics.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize theme from Telegram WebApp
    AppTheme.initialize();
    
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
          title: "Hype N' Links",
          builder: (context, child) {
            return SizedBox.expand(
              child: Container(
                color: AppTheme.backgroundColor,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (child != null) child,
                    const GlobalLogoBar(),
                    const GlobalBottomBar(),
                    // Show overlay when input is focused
                    ValueListenableBuilder<bool>(
                      valueListenable: GlobalBottomBar.focusNotifier,
                      builder: (context, isFocused, _) {
                        return isFocused ? const AiSearchOverlay() : const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
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
      home: const MainPage(),
        );
      },
    );
  }
}
