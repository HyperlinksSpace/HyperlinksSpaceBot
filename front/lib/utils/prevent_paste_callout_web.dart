import 'dart:html' as html;

/// Registers document-level listeners to prevent the native Paste/callout menu on tap/long-press
/// (e.g. on Get/Key buttons in Telegram WebView). Runs in the same context as the Flutter app.
void initPreventPasteCallout() {
  bool isInputOrTextarea(html.EventTarget? target) {
    if (target == null || target is! html.Element) return false;
    final el = target;
    final tag = el.tagName.toLowerCase();
    if (tag == 'input' || tag == 'textarea') return true;
    html.Element? p = el.parent;
    while (p != null) {
      if (p.tagName.toLowerCase() == 'input' || p.tagName.toLowerCase() == 'textarea') {
        return true;
      }
      p = p.parent;
    }
    return false;
  }

  html.document.addEventListener('contextmenu', (e) => e.preventDefault());
  html.document.addEventListener('selectstart', (e) => e.preventDefault());
  html.document.addEventListener('touchstart', (e) {
    if (e is! html.TouchEvent) return;
    if (isInputOrTextarea(e.target)) return;
    e.preventDefault();
  }, true);
}
