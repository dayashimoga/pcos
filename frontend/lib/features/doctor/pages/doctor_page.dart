import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// PCOS Doctor — Environment validator that checks all system components,
/// isolates root causes from downstream cascade failures, and provides actionable remediation.
class DoctorPage extends StatefulWidget {
  const DoctorPage({super.key});

  @override
  State<DoctorPage> createState() => _DoctorPageState();
}

class _DoctorPageState extends State<DoctorPage> {
  bool _loading = true;
  final List<_Check> _checks = [];
  Map<String, dynamic>? _connectDiag;
  String? _rootCauseTitle;
  String? _rootCauseDetail;
  String? _rootCauseRemedy;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _loading = true;
      _checks.clear();
      _connectDiag = null;
      _rootCauseTitle = null;
      _rootCauseDetail = null;
      _rootCauseRemedy = null;
    });

    final api = getIt<ApiClient>();
    bool isServerReady = true;
    String? rootCauseReason;

    // ─── 1. Prerequisite Probe: Edge / Server Readiness (/readyz) ───
    await _runCheck('Control Plane Readiness',
        'Deep dependency check: JWT config, D1, Durable Objects', () async {
      try {
        final resp = await api.dio.get('/readyz');
        if (resp.data is Map) {
          final data = resp.data as Map;
          if (data['status'] == 'ready') {
            return 'Ready — Edge router, D1 database & bindings operational';
          }
        }
        return 'Control plane active';
      } catch (e) {
        if (e is DioException) {
          if (e.response?.statusCode == 503) {
            final data = e.response?.data;
            if (data is Map && data['checks'] is Map) {
              final checks = data['checks'] as Map;
              if (checks['jwt_config']?['status'] == 'fail') {
                isServerReady = false;
                rootCauseReason = 'JWT_SECRET missing';
                _rootCauseTitle = 'Server Configuration Error: JWT_SECRET Missing';
                _rootCauseDetail = checks['jwt_config']?['detail'] ??
                    'JWT_SECRET secret is not configured on the Cloudflare Worker.';
                _rootCauseRemedy =
                    'Run: npx wrangler secret put JWT_SECRET\nOr add JWT_SECRET to GitHub Repository Secrets.';
                throw Exception(
                    checks['jwt_config']?['detail'] ?? 'JWT_SECRET not configured');
              }
              if (checks['d1_database']?['status'] == 'fail') {
                isServerReady = false;
                rootCauseReason = 'D1 database error';
                _rootCauseTitle = 'D1 Database Connection Error';
                _rootCauseDetail = checks['d1_database']?['detail'] ??
                    'D1 database binding failed or table is missing.';
                _rootCauseRemedy =
                    'Run: npx wrangler d1 execute pcos-control-db --file=./schema.sql --remote';
                throw Exception('D1 database connection error');
              }
            }
          } else if (e.response?.statusCode == 404) {
            // Local Rust standalone server (no /readyz endpoint); proceed to health probe
            return 'Standalone Backend (No /readyz probe)';
          }
        }

        final err = ApiClient.formatError(e);
        if (err.contains('JWT_SECRET') || err.contains('configuration error')) {
          isServerReady = false;
          rootCauseReason = 'JWT_SECRET missing';
          _rootCauseTitle = 'Server Configuration Error: JWT_SECRET Missing';
          _rootCauseDetail = err;
          _rootCauseRemedy =
              'Run: npx wrangler secret put JWT_SECRET\nOr add JWT_SECRET to GitHub Repository Secrets.';
        }
        rethrow;
      }
    });

    // ─── 2. Backend API Reachability (/health) ───
    await _runCheck('Backend API', 'Server process reachable and responding',
        () async {
      final resp = await api.dio.get('/health');
      final version =
          resp.data is Map ? (resp.data['version'] ?? '1.0.0') : '1.0.0';
      final uptime =
          resp.data is Map ? (resp.data['uptime_secs'] ?? 0) : 0;
      return 'v$version — uptime ${uptime}s';
    });

    // ─── 3–10. Authenticated Dependent Checks ───
    if (!isServerReady) {
      // Avoid cascading 10 doomed requests when root configuration failed
      final blockReason = 'Blocked: Root server configuration prerequisite failed (${rootCauseReason ?? 'Configuration Error'})';
      _addBlockedCheck('Database', 'PostgreSQL / D1 connection pool', blockReason);
      _addBlockedCheck('Authentication', 'JWT auth and session management', blockReason);
      _addBlockedCheck('File Storage', 'Storage directory / R2 accessible', blockReason);
      _addBlockedCheck('Search Engine', 'Full-text search index', blockReason);
      _addBlockedCheck('Admin API', 'System administration endpoints', blockReason);
      _addBlockedCheck('Sharing', 'Share link creation and management', blockReason);
      _addBlockedCheck('Device Sync', 'Device registration and sync', blockReason);
      _addBlockedCheck('Notifications', 'Notification delivery system', blockReason);
      _addBlockedCheck('Trash', 'Soft-delete and recovery system', blockReason);
    } else {
      // 3. Database
      await _runCheck('Database', 'PostgreSQL / D1 connection pool', () async {
        final resp = await api.dio.get('/api/v1/health');
        return resp.data['status'] == 'healthy'
            ? 'Connected (healthy)'
            : 'Degraded';
      });

      // 4. Authentication
      await _runCheck('Authentication', 'JWT auth and session management',
          () async {
        final resp = await api.dio.get('/api/v1/users/me');
        final email = resp.data['email'] ?? 'unknown';
        return 'Authenticated as $email';
      });

      // 5. File Storage
      await _runCheck('File Storage', 'Storage directory accessible', () async {
        final resp = await api.dio.get('/api/v1/storage/stats');
        final total = resp.data is Map ? (resp.data['total_files'] ?? 0) : 0;
        return 'Storage active ($total files stored)';
      });

      // 6. Search Engine
      await _runCheck('Search Engine', 'Full-text search index', () async {
        final resp = await api.dio
            .get('/api/v1/search', queryParameters: {'q': 'test'});
        int count = 0;
        if (resp.data is Map && resp.data['results'] is List) {
          count = (resp.data['results'] as List).length;
        }
        return 'Index available ($count results for test query)';
      });

      // 7. Admin API
      await _runCheck('Admin API', 'System administration endpoints', () async {
        try {
          final resp = await api.dio.get('/api/v1/admin/system');
          final users = resp.data is Map ? (resp.data['total_users'] ?? 0) : 0;
          final files = resp.data is Map ? (resp.data['total_files'] ?? 0) : 0;
          return 'Admin system OK ($users users, $files files)';
        } catch (e) {
          if (e is DioException && e.response?.statusCode == 403) {
            return 'Admin endpoints active (Role-guarded: Requires admin user)';
          }
          rethrow;
        }
      });

      // 8. Sharing
      await _runCheck('Sharing', 'Share link creation and management', () async {
        final resp = await api.dio.get('/api/v1/shares');
        int count = 0;
        if (resp.data is Map && resp.data['shares'] is List) {
          count = (resp.data['shares'] as List).length;
        } else if (resp.data is List) {
          count = (resp.data as List).length;
        }
        return '$count active share links';
      });

      // 9. Device Sync
      await _runCheck('Device Sync', 'Device registration and sync', () async {
        final resp = await api.dio.get('/api/v1/devices');
        int count = 0;
        if (resp.data is List) {
          count = (resp.data as List).length;
        } else if (resp.data is Map && resp.data['devices'] is List) {
          count = (resp.data['devices'] as List).length;
        }
        return '$count registered devices';
      });

      // 10. Notifications
      await _runCheck('Notifications', 'Notification delivery system', () async {
        await api.dio.get('/api/v1/notifications');
        return 'Service available';
      });

      // 11. Trash
      await _runCheck('Trash', 'Soft-delete and recovery system', () async {
        final resp = await api.dio.get('/api/v1/trash');
        int count = 0;
        if (resp.data is Map && resp.data['items'] is List) {
          count = (resp.data['items'] as List).length;
        } else if (resp.data is List) {
          count = (resp.data as List).length;
        }
        return '$count items in trash';
      });
    }

    // ─── 12. PCOS Connect & Network Diagnostics (Always runs, unauthenticated) ───
    await _runCheck(
        'PCOS Connect', 'Network, NAT/CGNAT and Remote Reachability', () async {
      final resp = await api.dio.get('/api/v1/doctor/connectivity');
      if (resp.data is Map) {
        final d = Map<String, dynamic>.from(resp.data as Map);
        setState(() => _connectDiag = d);
        final ip = d['lan_ip'] ?? 'unknown';
        final cgnat = d['is_cgnat'] == true ? ' [CGNAT detected]' : '';
        final provider = d['recommended_provider'] ?? 'Automatic';
        return 'LAN: $ip$cgnat — Recommended: $provider';
      }
      return 'Connected';
    });

    // ─── 13. Media Streaming Engine ───
    if (!isServerReady) {
      _addBlockedCheck('Media Server',
          'Direct-play Range streaming and playback',
          'Blocked: Prerequisite Server Configuration failed');
    } else {
      await _runCheck('Media Server',
          'Direct-play Range streaming and playback', () async {
        final resp = await api.dio.get('/api/v1/media/history');
        final count = resp.data is List ? (resp.data as List).length : 0;
        return 'Media Engine online ($count sessions)';
      });
    }

    setState(() => _loading = false);
  }

  void _addBlockedCheck(String name, String desc, String reason) {
    setState(() {
      _checks.add(_Check(
        name: name,
        description: desc,
        status: _CheckStatus.blocked,
        detail: reason,
      ));
    });
  }

  Future<void> _runCheck(
      String name, String desc, Future<String> Function() check) async {
    final c = _Check(
        name: name,
        description: desc,
        status: _CheckStatus.running,
        detail: 'Checking...');
    setState(() => _checks.add(c));
    try {
      final detail = await check();
      setState(() {
        final idx = _checks.indexWhere((ch) => ch.name == name);
        if (idx >= 0) {
          _checks[idx] = c.copyWith(status: _CheckStatus.pass, detail: detail);
        }
      });
    } catch (e) {
      setState(() {
        final idx = _checks.indexWhere((ch) => ch.name == name);
        if (idx >= 0) {
          _checks[idx] = c.copyWith(
              status: _CheckStatus.fail, detail: ApiClient.formatError(e));
        }
      });
    }
  }

  Color _getStatusColor(_CheckStatus status, BuildContext context) {
    switch (status) {
      case _CheckStatus.pass:
        return AppTheme.success;
      case _CheckStatus.fail:
        return AppTheme.error;
      case _CheckStatus.blocked:
        return Colors.orange.shade700;
      case _CheckStatus.warn:
        return AppTheme.warning;
      case _CheckStatus.running:
        return AppTheme.textMutedColor(context);
    }
  }

  IconData _getStatusIcon(_CheckStatus status) {
    switch (status) {
      case _CheckStatus.pass:
        return Icons.check_circle_rounded;
      case _CheckStatus.fail:
        return Icons.cancel_rounded;
      case _CheckStatus.blocked:
        return Icons.block_rounded;
      case _CheckStatus.warn:
        return Icons.warning_amber_rounded;
      case _CheckStatus.running:
        return Icons.hourglass_top_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _checks.where((c) => c.status == _CheckStatus.pass).length;
    final failed = _checks.where((c) => c.status == _CheckStatus.fail).length;
    final blocked = _checks.where((c) => c.status == _CheckStatus.blocked).length;
    final total = _checks.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('PCOS Doctor',
                    style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text('Environment health check and diagnostics',
                    style: Theme.of(context).textTheme.bodyLarge),
              ])),
          OutlinedButton.icon(
            onPressed: _loading ? null : _runDiagnostics,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Re-run'),
          ),
        ]),
        const SizedBox(height: 24),

        // ─── Root Cause Diagnosis Card ───
        if (_rootCauseTitle != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.error, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _rootCauseTitle!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_rootCauseDetail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _rootCauseDetail!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                ],
                if (_rootCauseRemedy != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal_rounded,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'Remediation Command / Action:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textMutedColor(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _rootCauseRemedy!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ─── Summary card ───
        if (!_loading && _checks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: failed == 0 && blocked == 0
                  ? AppTheme.success.withOpacity(0.08)
                  : AppTheme.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: failed == 0 && blocked == 0
                      ? AppTheme.success.withOpacity(0.3)
                      : AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(
                  failed == 0 && blocked == 0
                      ? Icons.verified_rounded
                      : Icons.warning_rounded,
                  size: 36,
                  color: failed == 0 && blocked == 0
                      ? AppTheme.success
                      : AppTheme.warning),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      failed == 0 && blocked == 0
                          ? 'All Systems Operational'
                          : failed > 0
                              ? '$failed root issue${failed == 1 ? '' : 's'} detected${blocked > 0 ? ' ($blocked blocked)' : ''}'
                              : '$blocked check${blocked == 1 ? '' : 's'} blocked',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: failed == 0 && blocked == 0
                              ? AppTheme.success
                              : AppTheme.warning),
                    ),
                    Text(
                        '$passed passed, $failed failed${blocked > 0 ? ', $blocked blocked' : ''} (Total: $total)',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context))),
                  ])),
            ]),
          ),
        const SizedBox(height: 24),

        // PCOS Connect Diagnostics Card
        if (_connectDiag != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.cloud_sync_rounded,
                    color: AppTheme.primary, size: 24),
                const SizedBox(width: 10),
                Text(
                  'PCOS Connect — Zero-Config Remote Access',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: AppTheme.primary.withOpacity(0.4)),
                  ),
                  child: Text(
                    _connectDiag!['recommended_provider'] as String? ??
                        'Automatic',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 20, runSpacing: 12, children: [
                _buildInfoBadge('LAN IP',
                    _connectDiag!['lan_ip']?.toString() ?? 'Unknown', context),
                _buildInfoBadge(
                    'Hostname',
                    _connectDiag!['hostname']?.toString() ?? 'pcos-server',
                    context),
                _buildInfoBadge(
                  'NAT / CGNAT',
                  _connectDiag!['is_cgnat'] == true
                      ? 'CGNAT (Inbound Blocked)'
                      : 'Standard LAN / Route',
                  context,
                  color: _connectDiag!['is_cgnat'] == true
                      ? AppTheme.warning
                      : AppTheme.success,
                ),
                _buildInfoBadge(
                  'TLS Encryption',
                  _connectDiag!['tls_enabled'] == true
                      ? 'HTTPS Active'
                      : 'Automatic Caddy Proxy',
                  context,
                  color: AppTheme.success,
                ),
              ]),
              if (_connectDiag!['recommendations'] is List &&
                  (_connectDiag!['recommendations'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text('Recommendations:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMutedColor(context))),
                const SizedBox(height: 6),
                ...(_connectDiag!['recommendations'] as List).map(
                  (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(color: AppTheme.primary)),
                          Expanded(
                            child: Text(
                              rec.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textPrimaryColor(context),
                              ),
                            ),
                          ),
                        ]),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),
        ],

        // Checks list
        Container(
          decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor(context))),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: AppTheme.borderColor(context)))),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: Text('Component',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMutedColor(context)))),
                Expanded(
                    flex: 4,
                    child: Text('Status',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMutedColor(context)))),
                const SizedBox(
                    width: 24, child: Text('', style: TextStyle(fontSize: 12))),
              ]),
            ),
            ..._checks.map((c) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: AppTheme.borderColor(context),
                              width: 0.5))),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          AppTheme.textPrimaryColor(context))),
                              Text(c.description,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMutedColor(context))),
                            ])),
                    Expanded(
                        flex: 4,
                        child: Text(
                          c.detail,
                          style: TextStyle(
                              fontSize: 12,
                              color: _getStatusColor(c.status, context)),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        )),
                    SizedBox(
                        width: 24,
                        child: Icon(
                          _getStatusIcon(c.status),
                          size: 18,
                          color: _getStatusColor(c.status, context),
                        )),
                  ]),
                )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildInfoBadge(String label, String value, BuildContext context,
      {Color? color}) {
    final effectiveColor = color ?? AppTheme.textPrimaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMutedColor(context))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: effectiveColor)),
        ],
      ),
    );
  }
}

enum _CheckStatus { running, pass, fail, blocked, warn }

class _Check {
  final String name;
  final String description;
  final _CheckStatus status;
  final String detail;
  const _Check(
      {required this.name,
      required this.description,
      required this.status,
      required this.detail});

  _Check copyWith({_CheckStatus? status, String? detail}) => _Check(
      name: name,
      description: description,
      status: status ?? this.status,
      detail: detail ?? this.detail);
}
