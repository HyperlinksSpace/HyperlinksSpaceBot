import 'dart:js' as js;

/// Vercel Analytics integration for Flutter Web
class VercelAnalytics {
  static bool _initialized = false;

  /// Initialize Vercel Analytics
  /// This should be called once when the app starts
  /// Note: The script is loaded automatically by Vercel in production
  static void init() {
    if (_initialized) return;
    
    try {
      // Check if vercelAnalytics wrapper is available (set up in index.html)
      final vercelAnalytics = js.context['vercelAnalytics'];
      if (vercelAnalytics != null) {
        _initialized = true;
        print('✓ Vercel Analytics initialized (via wrapper)');
        return;
      }
      
      // Also check if va (Vercel Analytics) is directly available
      final va = js.context['va'];
      if (va != null) {
        _initialized = true;
        print('✓ Vercel Analytics initialized (va detected)');
        return;
      }
      
      // Not available yet, retry with exponential backoff
      print('Vercel Analytics not available yet, will retry...');
      _retryInit(attempt: 1);
    } catch (e) {
      print('Error initializing Vercel Analytics: $e');
    }
  }
  
  /// Retry initialization with exponential backoff
  static void _retryInit({int attempt = 1, int maxAttempts = 5}) {
    if (_initialized || attempt > maxAttempts) {
      if (!_initialized && attempt > maxAttempts) {
        print('⚠ Vercel Analytics not available after $maxAttempts attempts (normal in local dev)');
      }
      return;
    }
    
    Future.delayed(Duration(milliseconds: 500 * attempt), () {
      if (_initialized) return;
      
      try {
        final vercelAnalytics = js.context['vercelAnalytics'];
        final va = js.context['va'];
        
        if (vercelAnalytics != null || va != null) {
          _initialized = true;
          print('✓ Vercel Analytics initialized (retry $attempt)');
        } else {
          _retryInit(attempt: attempt + 1, maxAttempts: maxAttempts);
        }
      } catch (e) {
        print('Error in retry $attempt: $e');
        _retryInit(attempt: attempt + 1, maxAttempts: maxAttempts);
      }
    });
  }

  /// Track a page view
  /// Vercel Analytics automatically tracks page views, but we can manually trigger
  static void trackPageView({String? path, String? title}) {
    try {
      // Try using vercelAnalytics wrapper first
      final vercelAnalytics = js.context['vercelAnalytics'];
      if (vercelAnalytics != null) {
        final pageview = vercelAnalytics['pageview'];
        if (pageview != null && pageview is js.JsFunction) {
          pageview.apply([]);
          print('✓ Vercel Analytics: Page view tracked via wrapper');
          return;
        }
      }
      
      // Also try calling va directly if available
      final va = js.context['va'];
      if (va != null) {
        if (va is js.JsFunction) {
          va.apply([]);
          print('✓ Vercel Analytics: Page view tracked via va()');
        } else if (va is js.JsObject) {
          // va might be an object with methods
          final vaTrack = va['track'];
          if (vaTrack != null && vaTrack is js.JsFunction) {
            vaTrack.apply(['pageview']);
            print('✓ Vercel Analytics: Page view tracked via va.track()');
          }
        }
      }
      
      // Fallback: Update browser history to trigger automatic page view tracking
      // Use js.context.callMethod to avoid "Illegal invocation" error
      if (path != null) {
        try {
          js.context.callMethod('eval', [
            'if (window.history && window.history.pushState) { window.history.pushState({}, "${title ?? ''}", "$path"); }'
          ]);
          print('✓ Vercel Analytics: Page view triggered via history: $path');
        } catch (e) {
          // Ignore history errors
        }
      }
    } catch (e) {
      print('Error tracking page view: $e');
    }
  }

  /// Track a custom event
  static void trackEvent(String name, {Map<String, String>? properties}) {
    try {
      // Try using vercelAnalytics wrapper first (most reliable)
      final vercelAnalytics = js.context['vercelAnalytics'];
      if (vercelAnalytics != null) {
        final track = vercelAnalytics['track'];
        if (track != null && track is js.JsFunction) {
          if (properties != null) {
            final props = js.JsObject.jsify(properties);
            track.apply([name, props]);
          } else {
            track.apply([name]);
          }
          print('✓ Vercel Analytics: Tracked event "$name"${properties != null ? " with properties" : ""}');
          return;
        }
      }
      
      // Fallback: use va.track directly
      final va = js.context['va'];
      if (va != null) {
        // va can be a function or an object with track method
        if (va is js.JsFunction) {
          // va is a function, call it directly
          va.apply([]);
          print('✓ Vercel Analytics: Tracked via va()');
        } else {
          // va is an object, try to get track method
          final vaTrack = va['track'];
          if (vaTrack != null && vaTrack is js.JsFunction) {
            if (properties != null) {
              final props = js.JsObject.jsify(properties);
              vaTrack.apply([name, props]);
            } else {
              vaTrack.apply([name]);
            }
            print('✓ Vercel Analytics: Tracked event "$name" via va.track');
            return;
          }
        }
      }
      
      print('⚠ Vercel Analytics: Event "$name" not tracked (analytics not available)');
    } catch (e) {
      print('Error tracking event: $e');
    }
  }
}


