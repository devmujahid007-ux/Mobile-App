import 'analyses_sse_impl_stub.dart'
    if (dart.library.html) 'analyses_sse_impl_html.dart' as impl;

/// Subscribe to `GET /api/analyses/stream` (SSE). Returns dispose callback, or `null`.
void Function()? openAnalysesSse(
  String absoluteUrl,
  void Function(Map<String, dynamic> event) onMessage,
  void Function() onFallback,
) =>
    impl.openAnalysesSse(absoluteUrl, onMessage, onFallback);
