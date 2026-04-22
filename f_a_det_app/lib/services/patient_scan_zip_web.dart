// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
// Web-only download helper; dart:html is the stable approach for blob downloads today.
import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> savePatientScanZip(Uint8List bytes, String filename) async {
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = safeName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  html.Url.revokeObjectUrl(url);
  return safeName;
}
