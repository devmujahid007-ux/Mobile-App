// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

/// Flutter web: live updates (parity with NeuroScanAi `Home.jsx` EventSource).
void Function()? openAnalysesSse(
  String absoluteUrl,
  void Function(Map<String, dynamic> event) onMessage,
  void Function() onFallback,
) {
  html.EventSource? es;
  try {
    es = html.EventSource(absoluteUrl);
  } catch (_) {
    onFallback();
    return null;
  }

  var fallbackCalled = false;
  void triggerFallback() {
    if (fallbackCalled) return;
    fallbackCalled = true;
    try {
      es?.close();
    } catch (_) {}
    onFallback();
  }

  es.onMessage.listen((e) {
    try {
      final raw = e.data;
      if (raw == null) return;
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        onMessage(decoded);
      }
    } catch (_) {}
  });
  es.onError.listen((_) => triggerFallback());

  return () {
    try {
      es?.close();
    } catch (_) {}
  };
}
