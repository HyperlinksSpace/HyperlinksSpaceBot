import 'package:flutter/material.dart';
import 'dart:js' as js;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../telegram_webapp.dart';

// Theme helper class
class AppTheme {
  static final ValueNotifier<String?> _colorSchemeNotifier = ValueNotifier<String?>(null);
  static bool _initialized = false;
  
  static ValueNotifier<String?> get colorSchemeNotifier => _colorSchemeNotifier;
  
  /// Initialize theme from Telegram WebApp or browser/system preference
  static void initialize() {
    // Prevent duplicate initialization to avoid unnecessary rebuilds
    if (_initialized) {
      print('[AppTheme] Already initialized, skipping duplicate initialization');
      return;
    }
    _initialized = true;
    
    final telegramWebApp = TelegramWebApp();
    
    // Use console.log directly for browser console visibility
    final console = js.context['console'];
    final log = console != null ? console['log'] : null;
    
    void consoleLog(String message) {
      print(message);
      if (log is js.JsFunction) {
        log.apply([message]);
      }
    }
    
    // Check if we're actually running in Telegram (not just that the script is loaded)
    // The Telegram WebApp script is loaded in HTML, but we need to verify we're actually in Telegram
    final isActuallyInTelegram = telegramWebApp.isActuallyInTelegram;
    
    if (isActuallyInTelegram) {
      // Use Telegram WebApp theme
      final colorScheme = telegramWebApp.colorScheme;
      // Only update notifier if value actually changed to prevent unnecessary rebuilds
      if (_colorSchemeNotifier.value != colorScheme) {
        _colorSchemeNotifier.value = colorScheme;
        consoleLog('[AppTheme] ✓ Initialized with Telegram WebApp colorScheme: $colorScheme');
      } else {
        consoleLog('[AppTheme] Theme already set to: $colorScheme, skipping update');
      }
      
      // Listen for theme changes in real-time
      // According to Telegram docs: when themeChanged event fires,
      // the WebApp object already has updated colorScheme and themeParams
      telegramWebApp.onThemeChanged(() {
        // Immediately read the new colorScheme from Telegram WebApp
        // The WebApp object (this) already contains the updated values
        final newColorScheme = telegramWebApp.colorScheme;
        print('Theme changed event received! New colorScheme: $newColorScheme');
        
        // Update the notifier immediately to trigger UI rebuild
        final oldColorScheme = _colorSchemeNotifier.value;
        if (oldColorScheme != newColorScheme) {
          _colorSchemeNotifier.value = newColorScheme;
          print('Theme updated from "$oldColorScheme" to "$newColorScheme"');
        } else {
          print('Theme value unchanged: $newColorScheme');
        }
      });
      consoleLog('[AppTheme] ✓ Theme change listener registered');
    } else {
      // Not in Telegram Mini App - use browser/system theme
      // Wrap in try-catch to prevent errors from breaking app initialization
      try {
        consoleLog('[AppTheme] Not in Telegram, initializing browser theme...');
        _initializeBrowserTheme();
      } catch (e) {
        // If browser theme detection fails, use default theme
        print('[AppTheme] Error initializing browser theme: $e');
        _colorSchemeNotifier.value = 'light'; // Default fallback
      }
    }
  }
  
  /// Initialize theme from browser/system preference
  static void _initializeBrowserTheme() {
    try {
      // Use console.log directly for browser console visibility
      final console = js.context['console'];
      final log = console != null ? console['log'] : null;
      
      void consoleLog(String message) {
        print(message);
        if (log is js.JsFunction) {
          log.apply([message]);
        }
      }
      
      consoleLog('[AppTheme] Initializing browser theme detection...');
      // Use JavaScript to detect browser/system theme preference
      // Priority: browser prefers-color-scheme > system
      try {
        // Use a simpler approach: call window.matchMedia directly via JS
        // Create a JS function that calls window.matchMedia
        const matchMediaCode = '''
          (function(query) {
            if (typeof window !== 'undefined' && window.matchMedia) {
              return window.matchMedia(query);
            }
            return null;
          })
        ''';
        
        final matchMediaFunc = js.context.callMethod('eval', [matchMediaCode]);
        
        if (matchMediaFunc == null || matchMediaFunc is! js.JsFunction) {
          consoleLog('[AppTheme] matchMedia function not available, using default dark theme');
          _colorSchemeNotifier.value = 'dark';
          return;
        }
        
        // Check for prefers-color-scheme media query
        consoleLog('[AppTheme] Calling matchMedia for dark mode...');
        final darkModeQuery = matchMediaFunc.apply(['(prefers-color-scheme: dark)']);
        consoleLog('[AppTheme] Dark mode query result: $darkModeQuery');
        
        if (darkModeQuery == null || darkModeQuery is! js.JsObject) {
          consoleLog('[AppTheme] Dark mode query failed, using default dark theme');
          _colorSchemeNotifier.value = 'dark';
          return;
        }
        
        final isDark = darkModeQuery['matches'];
        consoleLog('[AppTheme] Dark mode matches: $isDark');
        
        String detectedTheme;
        if (isDark == true) {
          detectedTheme = 'dark';
        } else {
          // Check light mode explicitly
          consoleLog('[AppTheme] Calling matchMedia for light mode...');
          final lightModeQuery = matchMediaFunc.apply(['(prefers-color-scheme: light)']);
          consoleLog('[AppTheme] Light mode query result: $lightModeQuery');
          
          if (lightModeQuery != null && lightModeQuery is js.JsObject && lightModeQuery['matches'] == true) {
            detectedTheme = 'light';
          } else {
            // Default to dark if no preference
            detectedTheme = 'dark';
          }
        }
        
        // Only update notifier if value actually changed to prevent unnecessary rebuilds
        if (_colorSchemeNotifier.value != detectedTheme) {
          _colorSchemeNotifier.value = detectedTheme;
          consoleLog('[AppTheme] ✓ Theme set to: $detectedTheme');
        } else {
          consoleLog('[AppTheme] Theme already set to: $detectedTheme, skipping update');
        }
        
        // Listen for theme changes using addEventListener (modern approach)
        final addEventListener = darkModeQuery['addEventListener'];
        if (addEventListener is js.JsFunction) {
          addEventListener.apply([
            'change',
            js.allowInterop((js.JsObject e) {
                    final target = e['target'];
                    final isDark = target != null && target is js.JsObject
                        ? target['matches'] == true
                        : (darkModeQuery['matches'] == true);
                    final newTheme = isDark ? 'dark' : 'light';
                    consoleLog('[AppTheme] 🔄 Browser theme changed to: $newTheme');
                    _colorSchemeNotifier.value = newTheme;
                  })
                ]);
          consoleLog('[AppTheme] ✓ Theme change listener registered (addEventListener)');
        } else {
          // Fallback to addListener (older browsers)
          final addListener = darkModeQuery['addListener'];
          if (addListener is js.JsFunction) {
            addListener.apply([
              js.allowInterop((js.JsObject e) {
                final isDark = e['matches'] == true;
                final newTheme = isDark ? 'dark' : 'light';
                consoleLog('[AppTheme] 🔄 Browser theme changed to: $newTheme');
                _colorSchemeNotifier.value = newTheme;
              })
            ]);
            consoleLog('[AppTheme] ✓ Theme change listener registered (addListener)');
          } else {
            consoleLog('[AppTheme] ⚠ Could not register theme change listener');
          }
        }
      } catch (e) {
        // Fallback: default to dark theme on any error
        _colorSchemeNotifier.value = 'dark';
        consoleLog('[AppTheme] ⚠ Error initializing browser theme: $e, defaulting to dark');
      }
    } catch (e, stackTrace) {
      // Fallback: default to dark theme
      _colorSchemeNotifier.value = 'dark';
      final console = js.context['console'];
      final log = console != null ? console['log'] : null;
      if (log is js.JsFunction) {
        log.apply(['[AppTheme] ❌ Error initializing theme: $e']);
        log.apply(['[AppTheme] Stack trace: $stackTrace']);
      }
      print('[AppTheme] ❌ Error initializing theme: $e');
      print('[AppTheme] Stack trace: $stackTrace');
    }
  }
  
  /// Manually refresh theme from Telegram WebApp or browser/system (useful for debugging or manual refresh)
  static void refreshTheme() {
    final telegramWebApp = TelegramWebApp();
    if (telegramWebApp.isActuallyInTelegram) {
      final colorScheme = telegramWebApp.colorScheme;
      if (_colorSchemeNotifier.value != colorScheme) {
        print('Manually refreshing theme to: $colorScheme');
        _colorSchemeNotifier.value = colorScheme;
      }
    } else {
      // Refresh browser theme
      _initializeBrowserTheme();
    }
  }
  
  /// Get current color scheme from Telegram, browser/system, or env variable
  static String? get _currentColorScheme {
    final telegramWebApp = TelegramWebApp();
    
    // Priority 1: Telegram WebApp theme
    if (telegramWebApp.isActuallyInTelegram) {
      final colorScheme = telegramWebApp.colorScheme;
      if (colorScheme != null) {
        return colorScheme;
      }
    }
    
    // Priority 2: Browser/system theme (if notifier already has a value)
    if (_colorSchemeNotifier.value != null) {
      return _colorSchemeNotifier.value;
    }
    
    // Priority 3: Detect browser/system theme on the fly
    try {
      final window = js.context['window'];
      if (window != null) {
        final matchMedia = window['matchMedia'];
        if (matchMedia is js.JsFunction) {
          final darkModeQuery = matchMedia.apply(['(prefers-color-scheme: dark)']);
          if (darkModeQuery != null && darkModeQuery['matches'] == true) {
            return 'dark';
          }
          final lightModeQuery = matchMedia.apply(['(prefers-color-scheme: light)']);
          if (lightModeQuery != null && lightModeQuery['matches'] == true) {
            return 'light';
          }
        }
      }
    } catch (e) {
      // Ignore errors
    }
    
    // Priority 4: Fallback to env variable for local development
    return dotenv.env['THEME'];
  }
  
  static bool get isLightTheme {
    final colorScheme = _colorSchemeNotifier.value ?? _currentColorScheme;
    return colorScheme?.toLowerCase() == 'light';
  }

  static bool get isDarkTheme => !isLightTheme;

  static Color get backgroundColor =>
      isLightTheme ? const Color(0xFFFAFAFA) : const Color(0xFF111111);

  static Color get textColor => isLightTheme ? const Color(0xFF111111) : const Color(0xFFFAFAFA);

  static Color get chartLineColor => isLightTheme ? const Color(0xFF111111) : const Color(0xFFFAFAFA);

  static Color get dotFillColor => isLightTheme ? const Color(0xFFFAFAFA) : const Color(0xFF111111);

  static Color get dotStrokeColor => isLightTheme ? const Color(0xFF111111) : const Color(0xFFFAFAFA);

  static Color get buttonBackgroundColor =>
      isLightTheme ? const Color(0xFF111111) : const Color(0xFFFAFAFA);

  static Color get buttonTextColor =>
      isLightTheme ? const Color(0xFFFAFAFA) : const Color(0xFF111111);

}

