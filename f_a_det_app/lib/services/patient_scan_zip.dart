import 'dart:typed_data';

import 'patient_scan_zip_stub.dart'
    if (dart.library.io) 'patient_scan_zip_io.dart'
    if (dart.library.html) 'patient_scan_zip_web.dart' as patient_zip_impl;

/// Saves patient scan bytes from [GET /mri/scan/{id}/download] (ZIP or single volume).
Future<String?> savePatientScanZip(Uint8List bytes, String filename) =>
    patient_zip_impl.savePatientScanZip(bytes, filename);
