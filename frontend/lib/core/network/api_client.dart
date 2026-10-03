import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../router/app_router.dart';

/// Centralized HTTP client with JWT token management.
class ApiClient {
  late final Dio dio;
  final SharedPreferences prefs;

  static const String _accessTokenKey = 'pcos_access_token';
  static const String _refreshTokenKey = 'pcos_refresh_token';
  static const String _serverUrlKey = 'pcos_server_url';

  static String formatError(dynamic error) {
    if (error is DioException) {
      // 1. Inspect structured JSON response from server
      dynamic data = error.response?.data;
      if (data is String && data.trim().startsWith('{')) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }

      if (data is Map) {
        if (data['error'] != null) return data['error'].toString();
        if (data['message'] != null) return data['message'].toString();
        if (data['detail'] != null) return data['detail'].toString();
      } else if (data is String &&
          data.trim().isNotEmpty &&
          !data.contains('<!DOCTYPE')) {
        // Short plain text error (prevent leaking raw HTML pages)
        final cleanText = data.trim();
        if (cleanText.length < 200) {
          return cleanText;
        }
      }

      // 2. HTTP Status Code fallbacks
      final status = error.response?.statusCode;
      if (status == 400) {
        return 'Invalid request parameters (400).';
      }
      if (status == 401) {
        return 'Invalid or expired credentials/pairing session (401).';
      }
      if (status == 403) {
        return 'Access denied. You do not have permission to access this resource (403).';
      }
      if (status == 404) {
        return 'The requested resource was not found (404).';
      }
      if (status == 409) {
        return 'Conflict with existing resource (409).';
      }
      if (status == 500) {
        return 'Server internal error (500). Please check server configuration and logs.';
      }
      if (status == 502) {
        return 'Bad Gateway (502). The PCOS edge or upstream backend is unreachable.';
      }
      if (status == 503) {
        return 'Service temporarily unavailable (503). Server may be configuring or degraded.';
      }
      if (status == 504) {
        return 'Gateway Timeout (504). Upstream service took too long to respond.';
      }

      // 3. Network connection error fallbacks
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Unable to connect to PCOS server. Please verify network connectivity and server status.';
      }
      if (error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out while communicating with PCOS server.';
      }
      if (error.type == DioExceptionType.badCertificate) {
        return 'SSL/TLS certificate verification failed.';
      }

      // 4. Default clean fallback for any other DioException
      return error.message?.isNotEmpty == true
          ? error.message!
          : 'Network communication error (${error.type.name})';
    }

    final str = error.toString();
    if (str.startsWith('Exception: ')) return str.substring(11);
    if (str.contains('DioException')) {
      return 'Network communication error';
    }
    return str;
  }

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

  static String normalizeUrl(String url) {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      if (cleanUrl.startsWith('192.168.') ||
          cleanUrl.startsWith('10.') ||
          cleanUrl.startsWith('172.16.') ||
          cleanUrl.startsWith('127.0.0.1') ||
          cleanUrl.startsWith('localhost')) {
        cleanUrl = 'http://$cleanUrl';
      } else {
        cleanUrl = 'https://$cleanUrl';
      }
    }
    return cleanUrl;
  }

  String get currentServerUrl {
    final stored = prefs.getString(_serverUrlKey);
    if (stored != null &&
        stored.isNotEmpty &&
        !stored.contains('api.pcos.pages.dev')) {
      return normalizeUrl(stored);
    }
    if (kIsWeb) {
      return Uri.base.origin;
    }
    final envUrl = _resolveBaseUrl();
    if (envUrl.isNotEmpty) {
      return normalizeUrl(envUrl);
    }
    const cloudUrl = String.fromEnvironment('CONTROL_PLANE_URL',
        defaultValue: 'https://pcos-control-plane.dayashimoga.workers.dev');
    if (cloudUrl.isNotEmpty && cloudUrl.startsWith('http')) {
      return normalizeUrl(cloudUrl);
    }
    return 'https://pcos-control-plane.dayashimoga.workers.dev';
  }

  Future<void> setServerUrl(String url) async {
    final cleanUrl = normalizeUrl(url);
    await prefs.setString(_serverUrlKey, cleanUrl);
    dio.options.baseUrl = cleanUrl;
  }

  /// Test connection to a candidate server URL.
  Future<String?> testServerUrl(String url) async {
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty) return 'Server URL cannot be empty';
    final testDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ));
    try {
      final resp = await testDio.get('$cleanUrl/health');
      if (resp.statusCode == 200) {
        return null; // Success
      }
      return 'Server returned HTTP status ${resp.statusCode}';
    } catch (e) {
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout) {
          return 'Connection timed out. Check firewall and IP ($cleanUrl).';
        }
        if (e.type == DioExceptionType.connectionError) {
          return 'Connection refused. Ensure PCOS is running and check port (e.g. :80 or :8080).';
        }
        if (e.response != null) {
          return 'Server returned status ${e.response?.statusCode}';
        }
      }
      return 'Connection failed: $e';
    }
  }

  ApiClient({required this.prefs}) {
    dio = Dio(BaseOptions(
      baseUrl: kIsWeb ? '' : currentServerUrl,
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
          final path = error.requestOptions.path;
          if (!path.contains('/auth/login') &&
              !path.contains('/auth/register') &&
              !path.contains('/auth/refresh')) {
            // Try to refresh the token
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry original request with new token
              final token = prefs.getString(_accessTokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } catch (e) {
                return handler.next(error);
              }
            } else {
              // Session expired & unrefreshable — clear tokens & redirect to login
              await clearTokens();
              AppRouter.router.go('/login');
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
    AppRouter.setAuthToken(accessToken);
  }

  /// Claim a pairing code from mobile device and request Web/Desktop user approval.
  Future<Map<String, dynamic>> claimPairingCode({
    required String code,
    String? enrollmentToken,
    String? serverUrl,
    required String deviceName,
    required String deviceType,
    required String os,
    String? osVersion,
    String? agentVersion,
    String? clientFingerprint,
  }) async {
    final cleanCode = code.trim().replaceAll(' ', '');
    final targetUrl = serverUrl != null && serverUrl.trim().isNotEmpty
        ? serverUrl.trim()
        : currentServerUrl;
    final normalizedUrl = normalizeUrl(targetUrl);

    final client = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    final res = await client.post('/api/v1/devices/pair/claim', data: {
      'pairing_code': cleanCode,
      if (enrollmentToken != null) 'enrollment_token': enrollmentToken,
      'device_name': deviceName,
      'device_type': deviceType,
      'os': os,
      'os_version': osVersion ?? '',
      'agent_version': agentVersion ?? '0.1.0',
      if (clientFingerprint != null) 'client_fingerprint': clientFingerprint,
    });

    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Invalid response from claim endpoint');
  }

  /// Get real-time status of a pairing session.
  Future<Map<String, dynamic>> getPairingStatus({
    String? code,
    String? token,
    String? serverUrl,
  }) async {
    final targetUrl = serverUrl != null && serverUrl.trim().isNotEmpty
        ? serverUrl.trim()
        : currentServerUrl;
    final normalizedUrl = normalizeUrl(targetUrl);

    final client = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ));

    final res =
        await client.get('/api/v1/devices/pair/status', queryParameters: {
      if (code != null) 'code': code.trim().replaceAll(' ', ''),
      if (token != null) 'token': token.trim(),
    });

    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Invalid status response from pairing server');
  }

  /// Approve or reject a candidate device from the Web/Desktop client.
  Future<Map<String, dynamic>> approvePairing({
    String? code,
    String? token,
    required bool approved,
  }) async {
    final res = await dio.post('/api/v1/devices/pair/approve', data: {
      if (code != null) 'pairing_code': code.trim().replaceAll(' ', ''),
      if (token != null) 'enrollment_token': token.trim(),
      'approved': approved,
    });

    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to approve pairing');
  }

  /// Redeem a 6-digit pairing code to enroll device and sign in automatically.
  Future<Map<String, dynamic>> redeemPairingCode(
    String code, {
    String? enrollmentToken,
    String? serverUrl,
  }) async {
    final cleanCode = code.trim().replaceAll(' ', '');
    final targetUrl = serverUrl != null && serverUrl.trim().isNotEmpty
        ? serverUrl.trim()
        : currentServerUrl;
    final normalizedUrl = normalizeUrl(targetUrl);

    final client = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    final res = await client.post('/api/v1/devices/pair/redeem', data: {
      'pairing_code': cleanCode,
      if (enrollmentToken != null) 'enrollment_token': enrollmentToken,
      'device_name': kIsWeb ? 'Web Client' : 'Mobile Phone',
      'device_type': kIsWeb ? 'web' : 'mobile',
      'os': defaultTargetPlatform.name,
    });

    if (res.data != null && res.data['access_token'] != null) {
      final access = res.data['access_token'] as String;
      final refresh = res.data['refresh_token'] as String;
      await setServerUrl(normalizedUrl);
      await saveTokens(access, refresh);
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Invalid response from pairing server');
  }

  /// Clear tokens on logout.
  Future<void> clearTokens() async {
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    AppRouter.setAuthToken(null);
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
      final base = dio.options.baseUrl;
      final refreshUrl =
          base.isEmpty ? '/api/v1/auth/refresh' : '$base/api/v1/auth/refresh';
      final response = await Dio().post(
        refreshUrl,
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

  /// Dispatch real-time remote commands (Play-on-TV, Send-to-Device)
  Future<Map<String, dynamic>> sendCommand({
    required String targetDeviceId,
    required String command,
    required Map<String, dynamic> payload,
  }) async {
    final res = await dio.post('/api/v1/control/commands', data: {
      'targetDeviceId': targetDeviceId,
      'command': command,
      'payload': payload,
    });
    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to dispatch control command');
  }

  /// Resolve optimal connection route (Direct LAN, P2P WireGuard, or Relay)
  Future<Map<String, dynamic>> getDeviceRoute(
    String targetDeviceId, {
    String? callerLanIp,
  }) async {
    final res = await dio.get(
      '/api/v1/devices/resolve/$targetDeviceId',
      queryParameters: {
        if (callerLanIp != null) 'callerLanIp': callerLanIp,
      },
    );
    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to resolve device route');
  }

  /// Fetch Cloudflare Free-Tier Guard usage & budget statistics
  Future<Map<String, dynamic>> getFreeTierUsage() async {
    final res = await dio.get('/api/v1/free-tier/usage');
    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to fetch free tier usage');
  }

  /// Update file availability policy (local_only, any_device, always_available, redundant, archive)
  Future<Map<String, dynamic>> setFileAvailability(
    String fileId,
    String availabilityTier,
  ) async {
    final res = await dio.put(
      '/api/v1/files/$fileId/availability',
      data: {'availability_tier': availabilityTier},
    );
    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to update file availability tier');
  }

  /// Request file replication to encrypted cloud cache or secondary node
  Future<Map<String, dynamic>> replicateFile(
    String fileId, {
    String target = 'r2_cache',
  }) async {
    final res = await dio.post(
      '/api/v1/files/$fileId/replicate',
      data: {'target': target},
    );
    if (res.data != null && res.data is Map) {
      return Map<String, dynamic>.from(res.data);
    }
    throw Exception('Failed to replicate file');
  }
}
