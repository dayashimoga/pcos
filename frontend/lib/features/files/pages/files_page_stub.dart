import 'package:flutter/material.dart';

/// Stub for non-web platforms — will use file_picker package.
void pickAndUploadFiles(BuildContext context, String? parentFolderId) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('File picking not available on this platform yet')),
  );
}
