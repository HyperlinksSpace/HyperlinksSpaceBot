import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_telegram_miniapp/flutter_telegram_miniapp.dart' as tma;
import 'api/auth_api.dart';
import 'telegram_webapp.dart';
import 'app/app.dart';
import 'app/theme/app_theme.dart';

void main() async {
  // Load .env file for local development
  try {
    await dotenv.load(fileName: ".env");
    print('Loaded .env file for local development');
  } catch (e) {
    print('No .env file found (this is OK for production): $e');
  }

  // On web, prefetch BOT_API_URL from /api/config so production (Vercel) has URL without .env
  if (kIsWeb) {
    await AuthApi.resolveBaseUrlAsync();
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

  runApp(const MyApp());
}
