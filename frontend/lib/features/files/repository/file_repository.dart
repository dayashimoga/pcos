// ignore: unused_import
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

class FileRepository {
  final ApiClient apiClient;
  FileRepository({required this.apiClient});

  Future<Map<String, dynamic>> listRoot() async {
    final r = await apiClient.dio.get('/api/v1/folders');
    return r.data;
  }

  Future<Map<String, dynamic>> listFolder(String folderId) async {
    final r = await apiClient.dio.get('/api/v1/folders/$folderId');
    return r.data;
  }

  Future<Map<String, dynamic>> uploadFile(
      String filename, List<int> bytes, String? parentId) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (parentId != null) 'parent_id': parentId,
    });
    final r = await apiClient.dio.post('/api/v1/files/upload', data: formData);
    return r.data;
  }

  Future<Map<String, dynamic>> createFolder(
      String name, String? parentId) async {
    final r = await apiClient.dio.post('/api/v1/folders', data: {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return r.data;
  }

  Future<void> deleteItem(String itemId) async {
    await apiClient.dio.delete('/api/v1/files/$itemId');
  }

  Future<void> renameItem(String itemId, String newName) async {
    await apiClient.dio.put('/api/v1/files/$itemId', data: {'name': newName});
  }

  Future<void> moveItem(String itemId, String? targetFolderId) async {
    await apiClient.dio.put('/api/v1/files/$itemId/move',
        data: {'target_folder_id': targetFolderId});
  }

  Future<List<dynamic>> listTrash() async {
    final r = await apiClient.dio.get('/api/v1/trash');
    return r.data;
  }

  Future<void> restoreFromTrash(String itemId) async {
    await apiClient.dio.post('/api/v1/trash/$itemId/restore');
  }

  Future<void> emptyTrash() async {
    await apiClient.dio.post('/api/v1/trash/empty');
  }

  Future<Map<String, dynamic>> storageStats() async {
    final r = await apiClient.dio.get('/api/v1/storage/stats');
    return r.data;
  }

  Future<Map<String, dynamic>> search(String query) async {
    final r = await apiClient.dio
        .get('/api/v1/search', queryParameters: {'q': query});
    return r.data;
  }

  Future<void> toggleFavorite(String itemId) async {
    await apiClient.dio.put('/api/v1/files/$itemId/favorite');
  }

  Future<void> bulkDelete(List<String> itemIds) async {
    await apiClient.dio
        .post('/api/v1/files/bulk-delete', data: {'ids': itemIds});
  }

  String downloadUrl(String fileId) => '/api/v1/files/$fileId/download';
  String previewUrl(String fileId) => '/api/v1/files/$fileId/preview';
}
