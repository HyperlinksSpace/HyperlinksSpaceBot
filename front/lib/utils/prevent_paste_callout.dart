import 'prevent_paste_callout_stub.dart'
    if (dart.library.html) 'prevent_paste_callout_web.dart' as impl;

/// Call early (e.g. from main()) on web to prevent Paste callout on Get/Key tap in Telegram WebView.
void initPreventPasteCallout() => impl.initPreventPasteCallout();
