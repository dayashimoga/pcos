import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized HTTP client with JWT token management.
class ApiClient {
  late final Dio dio;
  final SharedPreferences prefs;

  static const String _accessTokenKey = 'pcos_access_token';
  static const String _refreshTokenKey = 'pcos_refresh_token';
  static const String _serverUrlKey = 'pcos_server_url';

  static String _resolveBaseUrl() {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl == '/' || envUrl.isEmpty) {
      return '';
    }
    if (envUrl.endsWith('/')) {
      return envUrl.substring(0, envUrl.length - 1);
    }
    return envUrl;
  }

  String get currentServerUrl {
    final stored = prefs.getString(_serverUrlKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return _resolveBaseUrl();
  }

  Future<void> setServerUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'http://$cleanUrl';
    }
    await prefs.setString(_serverUrlKey, cleanUrl);
    dio.options.baseUrl = cleanUrl;
  }

  ApiClient({required this.prefs}) {
    final initialUrl = prefs.getString(_serverUrlKey) ?? _resolveBaseUrl();
    dio = Dio(BaseOptions(
      baseUrl: initialUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add auth interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = prefs.getString(_accessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh the token
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Retry the original request with new token
            final token = prefs.getString(_accessTokenKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        // Retry on network errors and 5xx (up to 2 retries)
        final int retryCount =
            (error.requestOptions.extra['_retryCount'] as int?) ?? 0;
        if (retryCount < 2 &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.connectionError ||
                (error.response?.statusCode ?? 0) >= 500)) {
          await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
          error.requestOptions.extra['_retryCount'] = retryCount + 1;
          try {
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          } catch (_) {}
        }
        return handler.next(error);
      },
    ));
  }

  /// Store tokens after login/register.
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  /// Clear tokens on logout.
  Future<void> clearTokens() async {
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  /// Check if user has stored tokens.
  bool get hasTokens => prefs.containsKey(_accessTokenKey);

  /// Get the stored refresh token.
  String? get refreshToken => prefs.getString(_refreshTokenKey);

  /// Attempt to refresh the access token.
  Future<bool> _refreshToken() async {
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null) return false;

    try {
      final response = await Dio().post(
        '${dio.options.baseUrl}api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        await saveTokens(data['access_token'], data['refresh_token']);
        return true;
      }
    } catch (_) {
      // Refresh failed, user needs to login again
      await clearTokens();
    }
    return false;
  }
}
