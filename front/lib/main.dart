import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import 'api/auth_api.dart';
import 'telegram_webapp.dart';
import 'app/app.dart';
import 'app/theme/app_theme.dart';
import 'utils/prevent_paste_callout.dart';

void main() async {
  // Load .env file for local development
  try {
    await dotenv.load(fileName: ".env");
    print('Loaded .env file for local development');
  } catch (e) {
    print('No .env file found (this is OK for production): $e');
  }

  // On web, prefetch BOT_API_URL in background so runApp isn't blocked (localhost may not serve /api/config)
  if (kIsWeb) {
    unawaited(AuthApi.resolveBaseUrlAsync());
  }

  // Initialize Telegram WebApp using flutter_telegram_miniapp package
  // This MUST be called BEFORE runApp() and BEFORE using any WebApp methods
  // It initializes the EventHandler which sets up all event listeners including backButtonClicked
  try {
    tma.WebApp().init();
    print('Telegram WebApp initialized via flutter_telegram_miniapp');
  } catch (e) {
    print('Error initializing Telegram WebApp: $e');
    // Fallback to old initialization if package fails
    final telegramWebApp = TelegramWebApp();
    await telegramWebApp.initialize();
  }
  
  // Initialize theme from Telegram WebApp (will be called again in MyAppState, but this ensures early initialization)
  AppTheme.initialize();

  // On web: prevent native Paste callout on Get/Key tap (Telegram WebView). Register from Flutter so we run in app context.
  if (kIsWeb) {
    initPreventPasteCallout();
  }

  runApp(const MyApp());
}
