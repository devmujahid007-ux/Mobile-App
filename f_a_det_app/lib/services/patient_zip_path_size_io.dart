import 'dart:io' show File;

Future<int?> patientZipFileLength(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return null;
  }
}
