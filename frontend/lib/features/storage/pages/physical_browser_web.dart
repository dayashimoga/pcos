// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, use_build_context_synchronously
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/repository/file_repository.dart';

/// Download file over web browser anchor element.
void downloadFileUrl(String url, String filename) {
  final anchor = html.AnchorElement(href: url)
    ..target = '_blank'
    ..download = filename;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}

/// Web-specific file upload directly to physical PCOS Storage Node.
void pickAndUploadToNode({
  required BuildContext context,
  required String nodeId,
  required String currentPath,
  required VoidCallback onComplete,
}) {
  final repo = getIt<FileRepository>();
  final input = html.FileUploadInputElement()
    ..accept = '*/*'
    ..multiple = false;

  input.click();
  input.onChange.listen((event) {
    final files = input.files;
    if (files == null || files.isEmpty) return;
    final file = files.first;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) async {
      try {
        final bytes = reader.result as List<int>;
        final base64Data = base64Encode(bytes);
        final targetPath =
            currentPath.isEmpty ? file.name : '$currentPath/${file.name}';

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Uploading "${file.name}" to physical disk...'),
          backgroundColor: AppTheme.primary,
        ));

        // Write directly to physical storage node
        await repo.writeStorageNodeFsChunk(
          nodeId,
          targetPath,
          base64Data,
          offset: 0,
        );

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Uploaded "${file.name}" successfully!'),
          backgroundColor: AppTheme.success,
        ));

        onComplete();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.formatError(e)),
          backgroundColor: AppTheme.error,
        ));
      }
    });
  });
}
