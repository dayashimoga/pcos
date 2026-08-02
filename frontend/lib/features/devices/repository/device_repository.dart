import '../../../core/network/api_client.dart';

/// Repository for device management operations.
class DeviceRepository {
  final ApiClient apiClient;

  DeviceRepository({required this.apiClient});

  /// List all devices for the current user.
  Future<Map<String, dynamic>> listDevices() async {
    final response = await apiClient.dio.get('/api/v1/devices');
    return response.data;
  }

  /// Register a new device.
  Future<Map<String, dynamic>> registerDevice({
    required String name,
    required String deviceType,
    required String os,
    required String osVersion,
  }) async {
    final response = await apiClient.dio.post('/api/v1/devices', data: {
      'name': name,
      'device_type': deviceType,
      'os': os,
      'os_version': osVersion,
      'agent_version': '0.1.0',
    });
    return response.data;
  }

  /// Remove a device by ID.
  Future<void> removeDevice(String deviceId) async {
    await apiClient.dio.delete('/api/v1/devices/$deviceId');
  }
}
