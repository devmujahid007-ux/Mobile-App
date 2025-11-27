import 'dart:async';
import 'package:flutter/material.dart';

class UploadMRIScreen extends StatefulWidget {
  const UploadMRIScreen({super.key});
  @override
  State<UploadMRIScreen> createState() => _UploadMRIScreenState();
}

class _UploadMRIScreenState extends State<UploadMRIScreen> {
  String? _selectedFileName;
  double _progress = 0.0;
  bool _uploading = false;
  String? _message;

  void _pickFile() {
    setState(() {
      _selectedFileName = 'sample_scan.dcm';
      _message = null;
    });
  }

  void _startUpload() {
    if (_selectedFileName == null) {
      setState(() => _message = 'Please choose a file first.');
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
      _message = null;
    });

    Timer.periodic(const Duration(milliseconds: 300), (t) {
      setState(() => _progress += 12);
      if (_progress >= 100) {
        t.cancel();
        setState(() {
          _uploading = false;
          _message = 'Upload successful (mock). Ready for analysis.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload MRI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      // ignore: deprecated_member_use
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8)
                ]),
            child: Column(children: [
              Icon(Icons.cloud_upload, size: 48, color: Colors.blue.shade700),
              const SizedBox(height: 8),
              Text(_selectedFileName ?? 'No file selected',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Supported: DICOM, PNG, JPG',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose File')),
              if (_uploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _progress / 100),
                const SizedBox(height: 6),
                Text('${_progress.toInt()}%'),
              ]
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: ElevatedButton(
                    onPressed: _uploading ? null : _startUpload,
                    child: const Text('Upload'))),
            const SizedBox(width: 12),
            OutlinedButton(
                onPressed: () => Navigator.of(context).pushNamed('/results'),
                child: const Text('View Results')),
          ]),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!,
                style: TextStyle(
                    color: _message!.startsWith('Upload')
                        ? Colors.green.shade700
                        : Colors.red)),
          ]
        ]),
      ),
    );
  }
}
