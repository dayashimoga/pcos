import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';

/// Repository for authentication operations.
class AuthRepository {
  final ApiClient apiClient;
  final SharedPreferences prefs;

  AuthRepository({required this.apiClient, required this.prefs});

  /// Register a new user account.
  Future<Map<String, dynamic>> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final response = await apiClient.dio.post('/api/v1/auth/register', data: {
      'email': email,
      'display_name': displayName,
      'password': password,
    });

    final data = response.data;
    await apiClient.saveTokens(
      data['tokens']['access_token'],
      data['tokens']['refresh_token'],
    );
    return data;
  }

  /// Login with email and password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await apiClient.dio.post('/api/v1/auth/login', data: {
      'email': email,
      'password': password,
    });

    final data = response.data;
    await apiClient.saveTokens(
      data['tokens']['access_token'],
      data['tokens']['refresh_token'],
    );
    return data;
  }

  /// Get current user profile (checks if tokens are valid).
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (!apiClient.hasTokens) return null;

    try {
      final response = await apiClient.dio.get('/api/v1/users/me');
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await apiClient.clearTokens();
        return null;
      }
      rethrow;
    }
  }

  /// Logout and revoke refresh token.
  Future<void> logout() async {
    final refreshToken = apiClient.refreshToken;
    if (refreshToken != null) {
      try {
        await apiClient.dio.post('/api/v1/auth/logout', data: {
          'refresh_token': refreshToken,
        });
      } catch (_) {
        // Best-effort logout
      }
    }
    await apiClient.clearTokens();
  }
}
