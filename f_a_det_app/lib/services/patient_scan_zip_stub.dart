import 'dart:typed_data';

/// Fallback when neither `dart:io` nor `dart:html` is available.
Future<String?> savePatientScanZip(Uint8List bytes, String filename) async => null;
