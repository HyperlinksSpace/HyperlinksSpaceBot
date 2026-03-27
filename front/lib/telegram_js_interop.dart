// JS Interop helpers for Telegram WebApp API
// Using dart:js for compatibility, but with cleaner API

import 'dart:js' as js;
import 'dart:js_interop';

/// Helper to call BackButton.onClick(callback) using JS interop
void backButtonOnClickJsInterop(JSFunction callback) {
  try {
    final webApp = js.context['Telegram']?['WebApp'];
    if (webApp != null) {
      final backButton = webApp['BackButton'];
      if (backButton != null) {
        final onClick = backButton['onClick'];
        if (onClick is js.JsFunction) {
          // Convert JSFunction to JsObject for dart:js
          onClick.apply([callback]);
        }
      }
    }
  } catch (e) {
    // Ignore
  }
}

/// Helper to call WebApp.onEvent(eventType, callback) using JS interop
void webAppOnEventJsInterop(String eventType, JSFunction callback) {
  try {
    final webApp = js.context['Telegram']?['WebApp'];
    if (webApp != null) {
      final onEvent = webApp['onEvent'];
      if (onEvent is js.JsFunction) {
        onEvent.apply([eventType, callback]);
      }
    }
  } catch (e) {
    // Ignore
  }
}

