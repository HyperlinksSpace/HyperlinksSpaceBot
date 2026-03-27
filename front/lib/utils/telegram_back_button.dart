import 'dart:js' as js;
import 'dart:async';

class TelegramBackButton {
  // Store callback references so offClick can properly remove them
  static final Map<Function(), dynamic> _callbackMap = {};

  // CRITICAL: Store callbacks globally to prevent garbage collection
  static final List<dynamic> _globalCallbacks = [];
  
  // Log collector for displaying logs on screen
  static final List<String> _logs = [];
  static final _logController = StreamController<String>.broadcast();
  
  /// Stream of log messages
  static Stream<String> get logStream => _logController.stream;
  
  /// Get recent logs
  static List<String> get recentLogs => List.unmodifiable(_logs);
  
  /// Add a log message (both to console and log list)
  static void addLog(String message) {
    _addLog(message);
  }
  
  static void _addLog(String message) {
    print(message); // Also print to console
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    _logs.add(logMessage);
    if (_logs.length > 50) {
      _logs.removeAt(0); // Keep only last 50 logs
    }
    _logController.add(logMessage);
  }

  /// Get the WebApp instance
  static js.JsObject? _getWebApp() {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) {
        _addLog('[BackButton] Telegram object not found');
        return null;
      }
      final webApp = telegram['WebApp'];
      if (webApp == null) {
        _addLog('[BackButton] WebApp object not found');
        return null;
      }
      if (webApp is! js.JsObject) {
        _addLog('[BackButton] WebApp is not a JsObject: ${webApp.runtimeType}');
        return null;
      }
      return webApp;
    } catch (e) {
      _addLog('[BackButton] Error getting WebApp: $e');
      return null;
    }
  }

  /// Get the BackButton object from WebApp
  static js.JsObject? _getBackButton() {
    try {
      final webApp = _getWebApp();
      if (webApp == null) return null;

      final backButton = webApp['BackButton'];
      if (backButton == null) {
        _addLog('[BackButton] BackButton object not found');
        return null;
      }
      if (backButton is! js.JsObject) {
        _addLog('[BackButton] BackButton is not a JsObject: ${backButton.runtimeType}');
        return null;
      }
      return backButton;
    } catch (e) {
      _addLog('[BackButton] Error getting BackButton: $e');
      return null;
    }
  }

  /// Setup a debug listener to catch all events (for troubleshooting)
  /// Also sets up window message listener to catch events from Telegram
  static void setupDebugEventListener() {
    try {
      final webApp = _getWebApp();
      if (webApp == null) {
        _addLog('[BackButton] Debug: WebApp not found for event listener');
        return;
      }

      final onEvent = webApp['onEvent'];
      if (onEvent != null && onEvent is js.JsFunction) {
        // Listen to back button events specifically
        final debugCallback = js.allowInterop((dynamic eventData) {
          _addLog('[BackButton] 🔍 DEBUG: Event callback triggered! Event data: $eventData');
        });

        // Try listening to the back_button_pressed event
        try {
          onEvent.apply(['back_button_pressed', debugCallback]);
          _addLog('[BackButton] Debug: Registered listener for "back_button_pressed"');
        } catch (e) {
          _addLog('[BackButton] Debug: Failed to register "back_button_pressed": $e');
        }
        
        // Also try backButtonClicked
        try {
          onEvent.apply(['backButtonClicked', debugCallback]);
          _addLog('[BackButton] Debug: Registered listener for "backButtonClicked"');
        } catch (e) {
          _addLog('[BackButton] Debug: Failed to register "backButtonClicked": $e');
        }
      }
      
      // Window message listener removed temporarily to debug page loading
    } catch (e) {
      _addLog('[BackButton] Debug: Error setting up debug listener: $e');
    }
  }

  /// Show the back button
  /// First tries BackButton.show(), then falls back to postEvent
  static void show() {
    try {
      final webApp = _getWebApp();
      if (webApp == null) {
        _addLog('[BackButton] WebApp not found');
        return;
      }

      // Method 1: Try using BackButton.show() directly (primary method)
    final backButton = _getBackButton();
    if (backButton != null) {
        final showMethod = backButton['show'];
        if (showMethod != null && showMethod is js.JsFunction) {
          try {
            showMethod.apply([]);
            _addLog('[BackButton] ✓ Show command sent via BackButton.show()');
            return;
          } catch (e) {
            _addLog('[BackButton] BackButton.show() failed: $e');
            // Fall through to postEvent
          }
        }
      }

      // Method 2: Fallback to postEvent
      final postEvent = webApp['postEvent'];
      if (postEvent != null && postEvent is js.JsFunction) {
        try {
          postEvent.apply([
            'web_app_setup_back_button',
            js.JsObject.jsify({'is_visible': true})
          ]);
          _addLog('[BackButton] ✓ Show command sent via postEvent (fallback)');
          return;
      } catch (e) {
          _addLog('[BackButton] postEvent failed: $e');
      }
      }

      _addLog('[BackButton] ✗ Could not show back button - no methods available');
    } catch (e) {
      _addLog('[BackButton] Error showing back button: $e');
    }
  }

  /// Hide the back button
  /// First tries BackButton.hide(), then falls back to postEvent
  static void hide() {
    try {
      final webApp = _getWebApp();
      if (webApp == null) {
        _addLog('[BackButton] WebApp not found');
        return;
      }

      // Method 1: Try using BackButton.hide() directly (primary method)
    final backButton = _getBackButton();
    if (backButton != null) {
        final hideMethod = backButton['hide'];
        if (hideMethod != null && hideMethod is js.JsFunction) {
          try {
            hideMethod.apply([]);
            _addLog('[BackButton] ✓ Hide command sent via BackButton.hide()');
            return;
          } catch (e) {
            _addLog('[BackButton] BackButton.hide() failed: $e');
            // Fall through to postEvent
          }
        }
      }

      // Method 2: Fallback to postEvent
      final postEvent = webApp['postEvent'];
      if (postEvent != null && postEvent is js.JsFunction) {
        try {
          postEvent.apply([
            'web_app_setup_back_button',
            js.JsObject.jsify({'is_visible': false})
          ]);
          _addLog('[BackButton] ✓ Hide command sent via postEvent (fallback)');
          return;
      } catch (e) {
          _addLog('[BackButton] postEvent failed: $e');
        }
      }

      _addLog('[BackButton] ✗ Could not hide back button - no methods available');
    } catch (e) {
      _addLog('[BackButton] Error hiding back button: $e');
    }
  }

  /// Register a callback for back button clicks
  /// Uses new JS interop API for better type safety
  /// Tries multiple methods:
  /// 1. BackButton.onClick() - Direct Telegram API
  /// 2. WebApp.onEvent('back_button_pressed') - Event-based (matches tma.js)
  /// 3. Window message listener - Catches postMessage events (backup)
  static void onClick(Function() callback) {
    try {
      // Remove any existing callback for this function to avoid duplicates
      if (_callbackMap.containsKey(callback)) {
        offClick(callback);
      }

      // Create a unique callback ID for storing on window
      final callbackId = 'telegram_back_btn_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create Dart callback using js.allowInterop
      final dartCallback = js.allowInterop((dynamic event) {
        _addLog('[BackButton] 🔔🔔🔔🔔🔔 CALLBACK FIRED! 🔔🔔🔔🔔🔔');
        _addLog('[BackButton] Event: $event');
        _addLog('[BackButton] Executing handler...');
        try {
            callback();
          _addLog('[BackButton] ✓ Handler executed successfully');
        } catch (e, stackTrace) {
          _addLog('[BackButton] ✗ Error in handler: $e');
          _addLog('[BackButton] Stack: $stackTrace');
        }
      });
      
      // CRITICAL: Create a NATIVE JavaScript function using eval
      // This ensures Telegram recognizes it as a proper JS function
      dynamic jsNativeCallback;
      try {
        // Step 1: Store Dart callback on window using a helper function
        // Create a storage function first
        js.context.callMethod('eval', [
          '''
          window._storeDartCallback_$callbackId = function(callback) {
            window._dartBackBtnCallback_$callbackId = callback;
          };
          '''
        ]);
        
        // Step 2: Call the storage function with the Dart callback
        final storeFunc = js.context.callMethod('eval', ['window._storeDartCallback_$callbackId']);
        if (storeFunc is js.JsFunction) {
          storeFunc.apply([dartCallback]);
        }
        _addLog('[BackButton] Stored Dart callback on window');
        
        // Step 3: Create a native JS function that calls the stored callback
        // Use a local variable to avoid string interpolation issues
        jsNativeCallback = js.context.callMethod('eval', [
          '''
          (function() {
            var id = '$callbackId';
            return function() {
              console.log('[BackButton] Native JS function called!');
              var callbackName = '_dartBackBtnCallback_' + id;
              if (window[callbackName]) {
                window[callbackName]();
              } else {
                console.error('[BackButton] Callback not found on window!');
              }
            };
          })()
          '''
        ]);
        
        _addLog('[BackButton] ✓ Created native JS function wrapper');
        _addLog('[BackButton] Native callback type: ${jsNativeCallback.runtimeType}');
      } catch (e, stackTrace) {
        _addLog('[BackButton] ✗ Could not create native JS function: $e');
        _addLog('[BackButton] Stack: $stackTrace');
        jsNativeCallback = null;
      }
      
      // Also create separate callbacks for event listeners
      final callbackBackButtonPressed = js.allowInterop((dynamic event) {
        _addLog('[BackButton] 🔔 EVENT: back_button_pressed fired!');
        callback();
      });
      
      final callbackBackButtonClicked = js.allowInterop((dynamic event) {
        _addLog('[BackButton] 🔔 EVENT: backButtonClicked fired!');
        callback();
      });

      _addLog('[BackButton] Created JavaScript callbacks');

      final webApp = _getWebApp();
      if (webApp == null) {
        _addLog('[BackButton] WebApp not found - cannot register onClick');
            return;
      }

      // Callback is already stored on window via eval above
      // This prevents garbage collection

      // METHOD 1: BackButton.onClick() via dart:js - PRIMARY for TMA built-in button
      // According to Telegram API: BackButton.onClick() is the direct method
      try {
        final backButton = _getBackButton();
        if (backButton != null) {
          final onClick = backButton['onClick'];
          if (onClick is js.JsFunction) {
            _addLog('[BackButton] Attempting BackButton.onClick() via dart:js...');
            _addLog('[BackButton] This is PRIMARY for TMA built-in button');
            // CRITICAL: Store callback in global list to prevent GC
            _globalCallbacks.add(dartCallback);
            if (jsNativeCallback != null) {
              _globalCallbacks.add(jsNativeCallback);
            }
            
            // Register the callback - use native JS function if available
            _addLog('[BackButton] Calling BackButton.onClick() with callback...');
            
            // Use native JS callback if we created one, otherwise use Dart callback
            final callbackToUse = jsNativeCallback ?? dartCallback;
            _addLog('[BackButton] Using callback type: ${callbackToUse.runtimeType}');
            
            try {
              onClick.apply([callbackToUse]);
              _callbackMap[callback] = callbackToUse;
              _globalCallbacks.add(callbackToUse);
              _addLog('[BackButton] ✓ Handler registered via BackButton.onClick() (METHOD 1 - PRIMARY)');
          } catch (e) {
              _addLog('[BackButton] ✗ onClick.apply() failed: $e');
              // Try alternative - use dartCallback directly
              try {
                onClick.apply([dartCallback]);
                _callbackMap[callback] = dartCallback;
                _globalCallbacks.add(dartCallback);
                _addLog('[BackButton] ✓ Handler registered using dartCallback fallback');
              } catch (e2) {
                _addLog('[BackButton] ✗ All registration methods failed: $e2');
                throw e;
        }
      }

            _addLog('[BackButton] ✓ Handler registered via BackButton.onClick() (METHOD 1 - PRIMARY)');
            _addLog('[BackButton] Callback stored globally (size: ${_globalCallbacks.length})');
            
            // Verify the callback was actually registered
            try {
              // Check if button is visible (should be false before show())
              final isVisible = backButton['isVisible'];
              _addLog('[BackButton] BackButton.isVisible: $isVisible');
            } catch (e) {
              _addLog('[BackButton] Could not check isVisible: $e');
            }
          } else {
            _addLog('[BackButton] ✗ BackButton.onClick is not a function: ${onClick.runtimeType}');
          }
        } else {
          _addLog('[BackButton] ✗ BackButton object not found');
        }
      } catch (e, stackTrace) {
        _addLog('[BackButton] ✗ BackButton.onClick() failed: $e');
        _addLog('[BackButton] Stack: $stackTrace');
      }
      
      // IMPORTANT: For TMA built-in buttons, the callback MUST be registered BEFORE show()
      // Verify this is the case by checking if button is visible
      try {
        final backButton = _getBackButton();
        if (backButton != null) {
          final isVisible = backButton['isVisible'];
          if (isVisible == true) {
            _addLog('[BackButton] ⚠️ WARNING: Button is already visible! Callback should be registered BEFORE show()');
          } else {
            _addLog('[BackButton] ✓ Button not visible yet - callback registered at correct time');
          }
        }
      } catch (e) {
        // Ignore
      }

      // METHOD 2: WebApp.onEvent('backButtonClicked') - Telegram API says this is the event name
      // According to Telegram API docs: BackButton.onClick() is alias for onEvent('backButtonClicked')
      try {
        final onEvent = webApp['onEvent'];
        if (onEvent != null && onEvent is js.JsFunction) {
          _addLog('[BackButton] Attempting WebApp.onEvent("backButtonClicked")...');
          _addLog('[BackButton] Telegram API: BackButton.onClick() = onEvent("backButtonClicked")');
          // Use separate callback to identify which event fires
          onEvent.apply(['backButtonClicked', callbackBackButtonClicked]);
          if (!_callbackMap.containsKey(callback)) {
            _callbackMap[callback] = callbackBackButtonClicked;
          }
          _addLog('[BackButton] ✓ Handler registered via onEvent("backButtonClicked") (METHOD 2)');
        }
      } catch (e) {
        _addLog('[BackButton] ✗ onEvent("backButtonClicked") failed: $e');
      }

      // METHOD 3: Also try 'back_button_pressed' (snake_case - tma.js uses this)
      try {
        final onEvent = webApp['onEvent'];
        if (onEvent != null && onEvent is js.JsFunction) {
          _addLog('[BackButton] Attempting WebApp.onEvent("back_button_pressed")...');
          _addLog('[BackButton] This is what tma.js SDK uses (snake_case)');
          // Use separate callback to identify which event fires
          onEvent.apply(['back_button_pressed', callbackBackButtonPressed]);
          _addLog('[BackButton] ✓ Handler registered via onEvent("back_button_pressed") (METHOD 3)');
        }
      } catch (e) {
        _addLog('[BackButton] ✗ onEvent("back_button_pressed") failed: $e');
      }
      
      // DEBUG: Listen to ALL events to see what Telegram actually sends
      try {
        final onEvent = webApp['onEvent'];
        if (onEvent != null && onEvent is js.JsFunction) {
          final debugAllEvents = js.allowInterop((dynamic eventData) {
            _addLog('[BackButton] 🔍 DEBUG: Received event! Data: $eventData, Type: ${eventData.runtimeType}');
          });
          // Try to listen to all possible event names
          final eventNames = ['back_button_pressed', 'backButtonClicked', 'backButton', 'back'];
          for (final eventName in eventNames) {
            try {
              onEvent.apply([eventName, debugAllEvents]);
              _addLog('[BackButton] Debug: Listening to "$eventName" events');
            } catch (e) {
              // Ignore
            }
        }
      }
    } catch (e) {
        _addLog('[BackButton] Could not set up debug event listeners: $e');
      }

      // METHOD 4: Window message listener (like tma.js bridge)
      // Use eval to create native JS event listener (bypasses dart:js limitations)
      try {
        // Use bracket notation to avoid string concatenation syntax errors
        final messageHandlerCode = '''
          (function() {
            var id = '$callbackId';
            function handleTelegramMessage(event) {
              if (event.source !== window.parent) return;
              var data = event.data;
              if (!data) return;
              
              try {
                var parsed = typeof data === 'string' ? JSON.parse(data) : data;
                if (parsed && parsed.eventType) {
                  console.log('[BackButton] Window message eventType:', parsed.eventType);
                  if (parsed.eventType === 'back_button_pressed' || parsed.eventType === 'backButtonClicked') {
                    console.log('[BackButton] 🔔🔔🔔 WINDOW MESSAGE: ' + parsed.eventType);
                    var callbackName = '_dartBackBtnCallback_' + id;
                    if (window[callbackName]) {
                      window[callbackName]();
                    }
                  }
                }
              } catch (e) {
                // Ignore parse errors
              }
            }
            window.addEventListener('message', handleTelegramMessage, false);
            window['_telegramMessageHandler_' + id] = handleTelegramMessage;
            console.log('[BackButton] Window message listener registered');
          })();
        ''';
        
        js.context.callMethod('eval', [messageHandlerCode]);
        _addLog('[BackButton] ✓ Window message listener registered via eval (METHOD 4)');
      } catch (e, stackTrace) {
        _addLog('[BackButton] Could not set up window message listener: $e');
        _addLog('[BackButton] Stack: $stackTrace');
      }

    } catch (e, stackTrace) {
      _addLog('[BackButton] ✗ Error setting up onClick: $e');
      _addLog('[BackButton] Stack trace: $stackTrace');
    }
  }

  /// Remove a callback for back button clicks
  /// Uses offEvent('back_button_pressed') to match tma.js SDK
  static void offClick(Function() callback) {
    try {
      final jsCallback = _callbackMap[callback];
      if (jsCallback == null) {
        _addLog('[BackButton] No callback found to remove');
        return;
      }

      final webApp = _getWebApp();
      if (webApp == null) {
        _addLog('[BackButton] WebApp not found - cannot remove onClick');
        return;
      }

      // Use offEvent('back_button_pressed') - matches tma.js SDK
        final offEvent = webApp['offEvent'];
      if (offEvent != null && offEvent is js.JsFunction) {
        try {
          offEvent.apply(['back_button_pressed', jsCallback]);
          _callbackMap.remove(callback);
          _addLog('[BackButton] ✓ Handler removed via offEvent("back_button_pressed")');
          return;
        } catch (e) {
          _addLog('[BackButton] offEvent("back_button_pressed") failed: $e');
        }
      } else {
        _addLog('[BackButton] ✗ offEvent method not found');
      }

      _addLog('[BackButton] ✗ Could not remove onClick');
    } catch (e) {
      _addLog('[BackButton] Error removing onClick: $e');
    }
  }
}

