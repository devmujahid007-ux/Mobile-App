import 'dart:io' show File;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> savePatientScanZip(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final path = '${dir.path}/$safeName';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
