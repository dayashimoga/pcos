import 'package:flutter/material.dart';

/// Stub download helper for non-web platforms.
void downloadFileUrl(String url, String filename) {}

/// Stub file picker for non-web platforms.
void pickAndUploadToNode({
  required BuildContext context,
  required String nodeId,
  required String currentPath,
  required VoidCallback onComplete,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Physical upload via desktop/mobile picker coming soon.'),
    ),
  );
}
