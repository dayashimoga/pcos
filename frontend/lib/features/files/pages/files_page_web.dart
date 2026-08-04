import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/file_bloc.dart';

/// Web-specific file picker using dart:html.
void pickAndUploadFiles(BuildContext context, String? parentFolderId) {
  final input = html.FileUploadInputElement()
    ..accept = '*/*'
    ..multiple = true;
  input.click();
  input.onChange.listen((event) {
    final files = input.files;
    if (files == null) return;
    for (final file in files) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        final bytes = (reader.result as List<int>);
        context.read<FileBloc>().add(FileUploadRequested(
              filename: file.name,
              bytes: bytes,
              parentId: parentFolderId,
            ));
      });
    }
  });
}
