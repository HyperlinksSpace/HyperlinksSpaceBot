import 'dart:js' as js;
import 'dart:async';

/// Represents safe area insets from Telegram
class SafeAreaInsets {
  final double top;
  final double bottom;
  final double left;
  final double right;

  SafeAreaInsets({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  factory SafeAreaInsets.fromJsObject(js.JsObject? obj) {
    if (obj == null) {
      return SafeAreaInsets.zero;
    }

    try {
      return SafeAreaInsets(
        top: _getDouble(obj, 'top') ?? 0.0,
        bottom: _getDouble(obj, 'bottom') ?? 0.0,
        left: _getDouble(obj, 'left') ?? 0.0,
        right: _getDouble(obj, 'right') ?? 0.0,
      );
    } catch (e) {
      return SafeAreaInsets.zero;
    }
  }

  static double? _getDouble(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    } catch (e) {
      return null;
    }
  }

  static SafeAreaInsets zero = SafeAreaInsets(
    top: 0.0,
    bottom: 0.0,
    left: 0.0,
    right: 0.0,
  );

  @override
  String toString() {
    return 'SafeAreaInsets(top: $top, bottom: $bottom, left: $left, right: $right)';
  }

  bool get isEmpty => top == 0 && bottom == 0 && left == 0 && right == 0;
}

/// Represents content safe area insets from Telegram
class ContentSafeAreaInsets {
  final double top;
  final double bottom;
  final double left;
  final double right;

  ContentSafeAreaInsets({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  factory ContentSafeAreaInsets.fromJsObject(js.JsObject? obj) {
    if (obj == null) {
      return ContentSafeAreaInsets.zero;
    }

    try {
      return ContentSafeAreaInsets(
        top: _getDouble(obj, 'top') ?? 0.0,
        bottom: _getDouble(obj, 'bottom') ?? 0.0,
        left: _getDouble(obj, 'left') ?? 0.0,
        right: _getDouble(obj, 'right') ?? 0.0,
      );
    } catch (e) {
      return ContentSafeAreaInsets.zero;
    }
  }

  static double? _getDouble(js.JsObject obj, String key) {
    try {
      final value = obj[key];
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    } catch (e) {
      return null;
    }
  }

  static ContentSafeAreaInsets zero = ContentSafeAreaInsets(
    top: 0.0,
    bottom: 0.0,
    left: 0.0,
    right: 0.0,
  );

  @override
  String toString() {
    return 'ContentSafeAreaInsets(top: $top, bottom: $bottom, left: $left, right: $right)';
  }

  bool get isEmpty => top == 0 && bottom == 0 && left == 0 && right == 0;
}

/// Service to get safe area insets from Telegram WebApp
class TelegramSafeAreaService {
  static final TelegramSafeAreaService _instance =
      TelegramSafeAreaService._internal();
  factory TelegramSafeAreaService() => _instance;
  TelegramSafeAreaService._internal();

  final _safeAreaController = StreamController<SafeAreaInsets>.broadcast();
  final _logController = StreamController<String>.broadcast();
  SafeAreaInsets _currentSafeArea = SafeAreaInsets.zero;
  bool _isInitialized = false;
  bool _isListening = false;
  final List<String> _logs = [];

  /// Stream of log messages
  Stream<String> get logStream => _logController.stream;

  /// Get recent logs
  List<String> get recentLogs => List.unmodifiable(_logs);

  /// Add a log message
  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    _logs.add(logMessage);
    if (_logs.length > 50) {
      _logs.removeAt(0);
    }
    _logController.add(logMessage);
  }

  /// Stream of safe area updates
  Stream<SafeAreaInsets> get safeAreaStream => _safeAreaController.stream;

  /// Current safe area insets
  SafeAreaInsets get currentSafeArea => _currentSafeArea;

  /// Check if TMA.js SDK is available
  bool get isTmaJsAvailable {
    try {
      final tmajs = js.context['tmajs'];
      if (tmajs == null) return false;
      final sdk = tmajs['sdk'];
      return sdk != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if Telegram WebApp is available
  bool get isAvailable {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) return false;
      final webApp = telegram['WebApp'];
      return webApp != null;
    } catch (e) {
      return false;
    }
  }

  /// Check if viewport is mounted and available
  bool _isViewportAvailable() {
    try {
      if (!isTmaJsAvailable) {
        _addLog('[_isViewportAvailable] TMA.js not available');
        return false;
      }

      final tmajs = js.context['tmajs'];
      if (tmajs == null) {
        _addLog('[_isViewportAvailable] tmajs is null');
        return false;
      }

      final sdk = tmajs['sdk'];
      if (sdk == null) {
        _addLog('[_isViewportAvailable] SDK is null');
        return false;
      }

      final viewport = sdk['viewport'];
      if (viewport == null) {
        _addLog('[_isViewportAvailable] viewport is null');
        return false;
      }

      // Check if mounted
      final isMounted = viewport['isMounted'];
      if (isMounted != null) {
        dynamic mountedValue;
        if (isMounted is js.JsFunction) {
          mountedValue = isMounted.apply([]);
        } else {
          mountedValue = isMounted;
        }

        if (mountedValue == true) {
          _addLog('[_isViewportAvailable] ✓ Viewport is mounted');
          return true;
        } else {
          _addLog(
              '[_isViewportAvailable] Viewport not mounted, isMounted = $mountedValue');
        }
      } else {
        _addLog('[_isViewportAvailable] isMounted property not found');
      }

      return false;
    } catch (e) {
      _addLog('[_isViewportAvailable] Error: $e');
      return false;
    }
  }

  /// Get individual inset value from viewport signal
  /// These methods return signals with numeric values directly
  /// Uses the same pattern as _getSafeAreaFromTmaJs but for numeric values
  // ignore: unused_element
  double _getInsetValue(String methodName) {
    try {
      if (!isTmaJsAvailable) {
        _addLog('[_getInsetValue] TMA.js not available for $methodName');
        return 0.0;
      }

      if (!_isViewportAvailable()) {
        _addLog(
            '[_getInsetValue] Viewport not mounted/available for $methodName');
        return 0.0;
      }

      final tmajs = js.context['tmajs'];
      if (tmajs == null) {
        _addLog('[_getInsetValue] tmajs null for $methodName');
        return 0.0;
      }

      final sdk = tmajs['sdk'];
      if (sdk == null) {
        _addLog('[_getInsetValue] SDK null for $methodName');
        return 0.0;
      }

      final viewport = sdk['viewport'];
      if (viewport == null) {
        _addLog('[_getInsetValue] viewport null for $methodName');
        return 0.0;
      }

      // Get the method (e.g., viewport.safeAreaInsetTop)
      final method = viewport[methodName];
      if (method == null) {
        _addLog('[_getInsetValue] Method $methodName not found');
        return 0.0;
      }

      _addLog('[_getInsetValue] Found $methodName');

      // Call the method to get the signal (same pattern as safeAreaInsets)
      dynamic signal;
      if (method is js.JsFunction) {
        signal = method.apply([]);
        _addLog('[_getInsetValue] Called $methodName()');
      } else {
        signal = method;
        _addLog('[_getInsetValue] $methodName is not a function');
      }

      if (signal == null) {
        _addLog('[_getInsetValue] Signal is null for $methodName');
        return 0.0;
      }

      // Get the value from the signal (same pattern as _getSafeAreaFromTmaJs)
      dynamic value;
      if (signal.hasProperty('value')) {
        value = signal['value'];
        _addLog(
            '[_getInsetValue] Got value from signal.value (type: ${value.runtimeType})');
      } else if (signal is js.JsFunction) {
        value = signal.apply([]);
        _addLog('[_getInsetValue] Called signal as function');
      } else {
        value = signal;
        _addLog('[_getInsetValue] Using signal as value');
      }

      if (value == null) {
        _addLog('[_getInsetValue] Value is null for $methodName');
        return 0.0;
      }

      // Convert to double (for numeric signals, value is a number)
      if (value is num) {
        final result = value.toDouble();
        _addLog('[_getInsetValue] ✓ $methodName = $result');
        return result;
      }
      if (value is String) {
        final result = double.tryParse(value) ?? 0.0;
        _addLog('[_getInsetValue] ✓ $methodName (from string) = $result');
        return result;
      }

      _addLog(
          '[_getInsetValue] Value not a number for $methodName: ${value.runtimeType}');
      return 0.0;
    } catch (e) {
      _addLog('[_getInsetValue] Error: $e');
      return 0.0;
    }
  }

  /// Get safeAreaInset object (NEW - device safe area, accounts for system UI)
  /// Directly from window.Telegram.WebApp.safeAreaInset
  SafeAreaInsets getSafeAreaInset() {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) {
        _addLog('[getSafeAreaInset] Telegram object not found');
        return SafeAreaInsets.zero;
      }

      final webApp = telegram['WebApp'];
      if (webApp == null) {
        _addLog('[getSafeAreaInset] WebApp object not found');
        return SafeAreaInsets.zero;
      }

      // Access safeAreaInset directly from Telegram.WebApp (NEW property)
      final safeAreaInset = webApp['safeAreaInset'];
      if (safeAreaInset != null) {
        _addLog('[getSafeAreaInset] Found safeAreaInset property on WebApp');

        if (safeAreaInset is js.JsObject) {
          final result = SafeAreaInsets.fromJsObject(safeAreaInset);
          _addLog('[getSafeAreaInset] ✓ Got: $result');
          return result;
        } else {
          _addLog(
              '[getSafeAreaInset] safeAreaInset is not a JsObject: ${safeAreaInset.runtimeType}');
        }
      } else {
        _addLog('[getSafeAreaInset] safeAreaInset property is null/undefined');
      }

      return SafeAreaInsets.zero;
    } catch (e) {
      _addLog('[getSafeAreaInset] Error: $e');
      return SafeAreaInsets.zero;
    }
  }

  /// Get contentSafeAreaInset object (NEW - content safe area, free from Telegram UI)
  /// Directly from window.Telegram.WebApp.contentSafeAreaInset
  ContentSafeAreaInsets getContentSafeAreaInset() {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) {
        _addLog('[getContentSafeAreaInset] Telegram object not found');
        return ContentSafeAreaInsets.zero;
      }

      final webApp = telegram['WebApp'];
      if (webApp == null) {
        _addLog('[getContentSafeAreaInset] WebApp object not found');
        return ContentSafeAreaInsets.zero;
      }

      // Access contentSafeAreaInset directly from Telegram.WebApp (NEW property)
      final contentSafeAreaInset = webApp['contentSafeAreaInset'];
      if (contentSafeAreaInset != null) {
        _addLog(
            '[getContentSafeAreaInset] Found contentSafeAreaInset property on WebApp');

        if (contentSafeAreaInset is js.JsObject) {
          final result =
              ContentSafeAreaInsets.fromJsObject(contentSafeAreaInset);
          _addLog('[getContentSafeAreaInset] ✓ Got: $result');
          return result;
        } else {
          _addLog(
              '[getContentSafeAreaInset] contentSafeAreaInset is not a JsObject: ${contentSafeAreaInset.runtimeType}');
        }
      } else {
        _addLog(
            '[getContentSafeAreaInset] contentSafeAreaInset property is null/undefined');
      }

      return ContentSafeAreaInsets.zero;
    } catch (e) {
      _addLog('[getContentSafeAreaInset] Error: $e');
      return ContentSafeAreaInsets.zero;
    }
  }

  /// Get all individual inset values
  /// Extracts from safeAreaInset and contentSafeAreaInset objects
  Map<String, double> getAllInsetValues() {
    // Get the two main objects (NEW methods)
    final safeAreaInset = getSafeAreaInset();
    final contentSafeAreaInset = getContentSafeAreaInset();

    return {
      'safeAreaInsetTop': safeAreaInset.top,
      'safeAreaInsetBottom': safeAreaInset.bottom,
      'safeAreaInsetLeft': safeAreaInset.left,
      'safeAreaInsetRight': safeAreaInset.right,
      'contentSafeAreaInsetTop': contentSafeAreaInset.top,
      'contentSafeAreaInsetBottom': contentSafeAreaInset.bottom,
      'contentSafeAreaInsetLeft': contentSafeAreaInset.left,
      'contentSafeAreaInsetRight': contentSafeAreaInset.right,
    };
  }

  /// Get content safe area insets
  ContentSafeAreaInsets getContentSafeArea() {
    try {
      if (!isTmaJsAvailable) return ContentSafeAreaInsets.zero;

      final tmajs = js.context['tmajs'];
      final sdk = tmajs['sdk'];
      final viewport = sdk['viewport'];

      if (viewport == null) return ContentSafeAreaInsets.zero;

      final contentSafeAreaInsetsSignal = viewport['contentSafeAreaInsets'];
      if (contentSafeAreaInsetsSignal == null) {
        return ContentSafeAreaInsets.zero;
      }

      dynamic signal;
      if (contentSafeAreaInsetsSignal is js.JsFunction) {
        signal = contentSafeAreaInsetsSignal.apply([]);
      } else {
        signal = contentSafeAreaInsetsSignal;
      }

      if (signal == null) return ContentSafeAreaInsets.zero;

      dynamic value;
      if (signal.hasProperty('value')) {
        value = signal['value'];
      } else if (signal is js.JsFunction) {
        value = signal.apply([]);
      } else {
        value = signal;
      }

      if (value == null) return ContentSafeAreaInsets.zero;

      if (value is js.JsObject) {
        return ContentSafeAreaInsets.fromJsObject(value);
      }

      return ContentSafeAreaInsets.zero;
    } catch (e) {
      return ContentSafeAreaInsets.zero;
    }
  }

  /// Mount TMA.js viewport component (required before accessing safe area)
  Future<bool> _mountViewport() async {
    try {
      if (!isTmaJsAvailable) {
        _addLog('[_mountViewport] TMA.js not available');
        return false;
      }

      final tmajs = js.context['tmajs'];
      if (tmajs == null) {
        _addLog('[_mountViewport] tmajs is null');
        return false;
      }

      final sdk = tmajs['sdk'];
      if (sdk == null) {
        _addLog('[_mountViewport] SDK is null');
        return false;
      }

      final viewport = sdk['viewport'];
      if (viewport == null) {
        _addLog('[_mountViewport] viewport is null');
        // Log what's available in SDK
        try {
          if (sdk is js.JsObject) {
            final keys = js.context.callMethod('Object.keys', [sdk]);
            if (keys != null) {
              final props = <String>[];
              final length = keys['length'];
              if (length is num) {
                for (var i = 0; i < length.toInt(); i++) {
                  final key = keys[i];
                  if (key is String) props.add(key);
                }
              }
              _addLog('[_mountViewport] SDK properties: $props');
            }
          }
        } catch (e) {
          _addLog('[_mountViewport] Error logging SDK props: $e');
        }
        return false;
      }

      _addLog('[_mountViewport] Viewport found');

      // Check if already mounted
      final isMounted = viewport['isMounted'];
      if (isMounted != null) {
        dynamic mountedValue;
        if (isMounted is js.JsFunction) {
          mountedValue = isMounted.apply([]);
        } else {
          mountedValue = isMounted;
        }

        if (mountedValue == true) {
          _addLog('[_mountViewport] Already mounted');
          return true;
        } else {
          _addLog(
              '[_mountViewport] Not mounted yet, isMounted = $mountedValue');
        }
      } else {
        _addLog('[_mountViewport] isMounted property not found');
      }

      final mount = viewport['mount'];
      if (mount == null) {
        _addLog('[_mountViewport] mount method not found');
        return false;
      }

      if (mount is js.JsFunction) {
        // Check if mount is available
        final mountAvailable = mount['isAvailable'];
        if (mountAvailable != null) {
          dynamic available;
          if (mountAvailable is js.JsFunction) {
            available = mountAvailable.apply([]);
          } else {
            available = mountAvailable;
          }

          if (available != true) {
            _addLog(
                '[_mountViewport] mount.isAvailable() = $available (not available)');
            return false;
          }
          _addLog('[_mountViewport] mount.isAvailable() = true');
        }

        // Call mount
        _addLog('[_mountViewport] Calling mount()...');
        mount.apply([]);

        // Wait a bit and check if it mounted
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify mount succeeded
        if (isMounted is js.JsFunction) {
          final mountedAfter = isMounted.apply([]);
          if (mountedAfter == true) {
            _addLog('[_mountViewport] ✓ Mount successful');
            return true;
          } else {
            _addLog(
                '[_mountViewport] Mount called but isMounted = $mountedAfter');
            return false;
          }
        }

        _addLog('[_mountViewport] Mount called (cannot verify)');
        return true;
      }

      _addLog('[_mountViewport] mount is not a function');
      return false;
    } catch (e) {
      _addLog('[_mountViewport] Error: $e');
      return false;
    }
  }

  /// Initialize and start listening for safe area changes
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Mount viewport if TMA.js is available - retry multiple times
      if (isTmaJsAvailable) {
        _addLog(
            '[initialize] TMA.js available, attempting to mount viewport...');

        bool mounted = false;
        for (int attempt = 1; attempt <= 3; attempt++) {
          _addLog('[initialize] Mount attempt $attempt/3');
          mounted = await _mountViewport();
          if (mounted) {
            _addLog('[initialize] ✓ Viewport mounted on attempt $attempt');
            break;
          }
          _addLog('[initialize] Mount attempt $attempt failed, retrying...');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (!mounted) {
          _addLog('[initialize] ✗ Failed to mount viewport after 3 attempts');
        }

        // Wait for viewport to be ready
        await Future.delayed(const Duration(milliseconds: 500));

        // Verify viewport is available
        if (_isViewportAvailable()) {
          _addLog('[initialize] ✓ Viewport is available and ready');
        } else {
          _addLog(
              '[initialize] ✗ Viewport is NOT available after mounting attempts');
        }
      } else {
        _addLog('[initialize] TMA.js not available, skipping viewport mount');
      }

      // Get initial safe area using NEW method (safeAreaInset)
      _addLog('[initialize] Getting initial safe area (getSafeAreaInset)...');
      final initialSafeArea = getSafeAreaInset();
      _addLog('[initialize] Initial safe area: $initialSafeArea');
      _updateSafeAreaIfValid(initialSafeArea, 'initialization');

      // Set up event listeners (only for orientation changes, not continuous polling)
      _setupEventListeners();

      _isInitialized = true;
    } catch (e) {
      print('Error initializing TelegramSafeAreaService: $e');
    }
  }

  /// Get safe area using TMA.js SDK viewport component
  /// This is the working method that successfully retrieves safe area
  SafeAreaInsets _getSafeAreaFromTmaJs() {
    try {
      if (!isTmaJsAvailable) {
        _addLog('[_getSafeAreaFromTmaJs] TMA.js not available');
        return SafeAreaInsets.zero;
      }

      if (!_isViewportAvailable()) {
        _addLog('[_getSafeAreaFromTmaJs] Viewport not mounted/available');
        return SafeAreaInsets.zero;
      }

      final tmajs = js.context['tmajs'];
      if (tmajs == null) {
        _addLog('[_getSafeAreaFromTmaJs] tmajs is null');
        return SafeAreaInsets.zero;
      }

      final sdk = tmajs['sdk'];
      if (sdk == null) {
        _addLog('[_getSafeAreaFromTmaJs] SDK is null');
        return SafeAreaInsets.zero;
      }

      final viewport = sdk['viewport'];
      if (viewport == null) {
        _addLog('[_getSafeAreaFromTmaJs] viewport is null');
        return SafeAreaInsets.zero;
      }

      final safeAreaInsetsSignal = viewport['safeAreaInsets'];
      if (safeAreaInsetsSignal == null) {
        _addLog('[_getSafeAreaFromTmaJs] safeAreaInsets is null');
        return SafeAreaInsets.zero;
      }

      _addLog(
          '[_getSafeAreaFromTmaJs] Found safeAreaInsets, type: ${safeAreaInsetsSignal.runtimeType}');

      dynamic signal;
      if (safeAreaInsetsSignal is js.JsFunction) {
        signal = safeAreaInsetsSignal.apply([]);
        _addLog('[_getSafeAreaFromTmaJs] Called safeAreaInsets(), got signal');
      } else {
        signal = safeAreaInsetsSignal;
        _addLog('[_getSafeAreaFromTmaJs] safeAreaInsets is not a function');
      }

      if (signal == null) {
        _addLog('[_getSafeAreaFromTmaJs] Signal is null');
        return SafeAreaInsets.zero;
      }

      dynamic value;
      if (signal.hasProperty('value')) {
        value = signal['value'];
        _addLog(
            '[_getSafeAreaFromTmaJs] Got value from signal.value (type: ${value.runtimeType})');
      } else if (signal is js.JsFunction) {
        value = signal.apply([]);
        _addLog('[_getSafeAreaFromTmaJs] Called signal as function');
      } else {
        value = signal;
        _addLog('[_getSafeAreaFromTmaJs] Using signal as value');
      }

      if (value == null) {
        _addLog('[_getSafeAreaFromTmaJs] Value is null');
        return SafeAreaInsets.zero;
      }

      if (value is js.JsObject) {
        final result = SafeAreaInsets.fromJsObject(value);
        _addLog(
            '[_getSafeAreaFromTmaJs] ✓ Parsed: top=${result.top}, bottom=${result.bottom}, left=${result.left}, right=${result.right}');
        return result;
      }

      _addLog(
          '[_getSafeAreaFromTmaJs] Value is not JsObject: ${value.runtimeType}');
      return SafeAreaInsets.zero;
    } catch (e) {
      _addLog('[_getSafeAreaFromTmaJs] Error: $e');
      return SafeAreaInsets.zero;
    }
  }

  /// Get safe area directly from Telegram WebApp (PRIMARY METHOD - this worked before!)
  SafeAreaInsets _getSafeAreaDirect() {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) {
        _addLog('[_getSafeAreaDirect] Telegram object not found');
        return SafeAreaInsets.zero;
      }

      final webApp = telegram['WebApp'];
      if (webApp == null) {
        _addLog('[_getSafeAreaDirect] WebApp object not found');
        return SafeAreaInsets.zero;
      }

      _addLog('[_getSafeAreaDirect] WebApp found, checking safeAreaInsets...');

      // Try direct property access (this is how we got 20px before!)
      final safeAreaInsets = webApp['safeAreaInsets'];
      if (safeAreaInsets != null) {
        _addLog('[_getSafeAreaDirect] Found safeAreaInsets property');

        SafeAreaInsets result;
        if (safeAreaInsets is js.JsObject) {
          result = SafeAreaInsets.fromJsObject(safeAreaInsets);
        } else {
          // Try to access properties directly
          try {
            final top = _getNumericProperty(safeAreaInsets, 'top');
            final bottom = _getNumericProperty(safeAreaInsets, 'bottom');
            final left = _getNumericProperty(safeAreaInsets, 'left');
            final right = _getNumericProperty(safeAreaInsets, 'right');
            result = SafeAreaInsets(
              top: top ?? 0.0,
              bottom: bottom ?? 0.0,
              left: left ?? 0.0,
              right: right ?? 0.0,
            );
          } catch (e) {
            _addLog('[_getSafeAreaDirect] Error parsing: $e');
            result = SafeAreaInsets.zero;
          }
        }

        _addLog('[_getSafeAreaDirect] ✓ Got safe area: $result');
        return result;
      } else {
        _addLog(
            '[_getSafeAreaDirect] safeAreaInsets property is null/undefined');
      }

      return SafeAreaInsets.zero;
    } catch (e) {
      _addLog('[_getSafeAreaDirect] Error: $e');
      return SafeAreaInsets.zero;
    }
  }

  double? _getNumericProperty(dynamic obj, String key) {
    try {
      if (obj is js.JsObject) {
        final value = obj[key];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get safe area - tries direct Telegram WebApp first (this worked before!), then TMA.js
  /// Always gets fresh values, doesn't use cached _currentSafeArea
  // ignore: unused_element
  SafeAreaInsets _getSafeArea() {
    // Try direct Telegram WebApp access FIRST (this is how we got 20px!)
    final directResult = _getSafeAreaDirect();
    if (!directResult.isEmpty) {
      _addLog('[_getSafeArea] ✓ Got from Telegram.WebApp: $directResult');
      return directResult;
    }

    // Fallback to TMA.js SDK viewport (if available and mounted)
    if (isTmaJsAvailable && _isViewportAvailable()) {
      final tmaResult = _getSafeAreaFromTmaJs();
      if (!tmaResult.isEmpty) {
        _addLog('[_getSafeArea] ✓ Got from TMA.js viewport: $tmaResult');
        return tmaResult;
      }
    }

    return SafeAreaInsets.zero;
  }

  /// Update safe area only if the new value is valid (non-zero) or current is zero
  void _updateSafeAreaIfValid(SafeAreaInsets newSafeArea, String source) {
    if (!newSafeArea.isEmpty && newSafeArea != _currentSafeArea) {
      _currentSafeArea = newSafeArea;
      _safeAreaController.add(_currentSafeArea);
      return;
    }

    if (newSafeArea.isEmpty && _currentSafeArea.isEmpty) {
      return;
    }

    if (newSafeArea.isEmpty && !_currentSafeArea.isEmpty) {
      return;
    }

    if (newSafeArea == _currentSafeArea) {
      return;
    }
  }

  /// Request safe area from Telegram (async)
  Future<SafeAreaInsets> requestSafeArea() async {
    try {
      if (!isAvailable) return SafeAreaInsets.zero;

      final telegram = js.context['Telegram'];
      final webApp = telegram['WebApp'];

      if (webApp != null) {
        try {
          final tmajs = js.context['tmajs'];
          if (tmajs != null) {
            final sdk = tmajs['sdk'];
            if (sdk != null) {
              final postEvent = sdk['postEvent'];
              if (postEvent != null) {
                postEvent.apply(['web_app_request_safe_area']);
              }
            }
          }
        } catch (e) {
          // Ignore
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));

      final newSafeArea = getSafeAreaInset();
      _updateSafeAreaIfValid(newSafeArea, 'requestSafeArea');

      return _currentSafeArea;
    } catch (e) {
      return SafeAreaInsets.zero;
    }
  }

  /// Set up event listeners for safe area changes
  void _setupEventListeners() {
    if (_isListening) return;

    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) return;

      final webApp = telegram['WebApp'];
      if (webApp == null) return;

      if (webApp.hasProperty('onEvent')) {
        final onEvent = webApp['onEvent'];
        if (onEvent != null) {
          try {
            onEvent.apply([
              'safeAreaChanged',
              js.allowInterop((dynamic data) {
                try {
                  SafeAreaInsets newSafeArea;
                  if (data is js.JsObject) {
                    newSafeArea = SafeAreaInsets.fromJsObject(data);
                  } else {
                    newSafeArea = getSafeAreaInset();
                  }
                  _updateSafeAreaIfValid(newSafeArea, 'safeAreaChanged event');
                } catch (e) {
                  // Ignore
                }
              })
            ]);
          } catch (e) {
            // Ignore
          }

          try {
            onEvent.apply([
              'viewportChanged',
              js.allowInterop((dynamic data) {
                // CRITICAL: Don't update safe area on viewportChanged during keyboard operations
                // Keyboard opening causes viewport changes, but safe area values should remain stable
                // Only update if this is a significant viewport change (orientation change, etc.)
                // We debounce and check if the change is significant before updating
                Future.delayed(const Duration(milliseconds: 300), () {
                  // Check if this is likely a keyboard-related viewport change
                  // by comparing with current safe area - if it's the same, skip update
                  final currentSafeArea = _currentSafeArea;
                  final newSafeArea = getSafeAreaInset();
                  
                  // Only update if safe area actually changed significantly (orientation change)
                  // Small changes are likely keyboard-related and should be ignored
                  if (newSafeArea != currentSafeArea && 
                      (newSafeArea.top != currentSafeArea.top || 
                       newSafeArea.bottom != currentSafeArea.bottom ||
                       newSafeArea.left != currentSafeArea.left ||
                       newSafeArea.right != currentSafeArea.right)) {
                    // Significant change - likely orientation change, not keyboard
                    _updateSafeAreaIfValid(newSafeArea, 'viewportChanged event (significant)');
                  }
                });
              })
            ]);
          } catch (e) {
            // Ignore
          }

          _isListening = true;
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  /// Get additional Telegram WebApp info for debugging
  Map<String, dynamic> getDebugInfo() {
    try {
      final telegram = js.context['Telegram'];
      if (telegram == null) {
        return {'error': 'Telegram object not found'};
      }

      final webApp = telegram['WebApp'];
      if (webApp == null) {
        return {'error': 'WebApp object not found'};
      }

      final info = <String, dynamic>{
        'isAvailable': true,
        'version': _getProperty(webApp, 'version'),
        'platform': _getProperty(webApp, 'platform'),
        'safeAreaInsets': {
          'top': _getProperty(webApp['safeAreaInsets'], 'top'),
          'bottom': _getProperty(webApp['safeAreaInsets'], 'bottom'),
          'left': _getProperty(webApp['safeAreaInsets'], 'left'),
          'right': _getProperty(webApp['safeAreaInsets'], 'right'),
        },
        'viewportHeight': _getProperty(webApp, 'viewportHeight'),
        'viewportStableHeight': _getProperty(webApp, 'viewportStableHeight'),
        'headerColor': _getProperty(webApp, 'headerColor'),
        'backgroundColor': _getProperty(webApp, 'backgroundColor'),
      };

      return info;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  dynamic _getProperty(dynamic obj, String key) {
    try {
      if (obj == null) return null;
      if (obj is js.JsObject) {
        return obj[key];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _safeAreaController.close();
    _logController.close();
  }
}
