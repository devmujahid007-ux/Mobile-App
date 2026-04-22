/// VM / mobile: no browser EventSource — caller uses HTTP polling only.
void Function()? openAnalysesSse(
  String absoluteUrl,
  void Function(Map<String, dynamic> event) onMessage,
  void Function() onFallback,
) =>
    null;
