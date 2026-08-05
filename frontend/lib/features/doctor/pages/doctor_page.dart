import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// PCOS Doctor — Environment validator that checks all system components.
class DoctorPage extends StatefulWidget {
  const DoctorPage({super.key});

  @override
  State<DoctorPage> createState() => _DoctorPageState();
}

class _DoctorPageState extends State<DoctorPage> {
  bool _loading = true;
  final List<_Check> _checks = [];

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _loading = true;
      _checks.clear();
    });

    final api = getIt<ApiClient>();

    // 1. Backend API
    await _runCheck('Backend API', 'Server reachable and responding', () async {
      final resp = await api.dio.get('/api/v1/health');
      return 'v${resp.data['version']} — uptime ${resp.data['uptime_secs']}s';
    });

    // 2. Database
    await _runCheck('Database', 'PostgreSQL connection pool', () async {
      final resp = await api.dio.get('/api/v1/health');
      return resp.data['status'] == 'healthy'
          ? 'Connected (healthy)'
          : 'Degraded';
    });

    // 3. Authentication
    await _runCheck('Authentication', 'JWT auth and session management',
        () async {
      final resp = await api.dio.get('/api/v1/users/me');
      final email = resp.data['email'] ?? 'unknown';
      return 'Authenticated as $email';
    });

    // 4. File Storage
    await _runCheck('File Storage', 'Storage directory accessible', () async {
      final resp = await api.dio.get('/api/v1/storage/stats');
      final total = resp.data is Map ? (resp.data['total_files'] ?? 0) : 0;
      return 'Storage active ($total files stored)';
    });

    // 5. Search Engine
    await _runCheck('Search Engine', 'Tantivy full-text search index',
        () async {
      final resp =
          await api.dio.get('/api/v1/search', queryParameters: {'q': 'test'});
      int count = 0;
      if (resp.data is Map && resp.data['results'] is List) {
        count = (resp.data['results'] as List).length;
      }
      return 'Index available ($count results for test query)';
    });

    // 6. Admin API
    await _runCheck('Admin API', 'System administration endpoints', () async {
      final resp = await api.dio.get('/api/v1/admin/system');
      final users = resp.data is Map ? (resp.data['total_users'] ?? 0) : 0;
      final files = resp.data is Map ? (resp.data['total_files'] ?? 0) : 0;
      return 'Admin system OK ($users users, $files files)';
    });

    // 7. Sharing
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

    // 8. Device Sync
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

    // 9. Notifications
    await _runCheck('Notifications', 'Notification delivery system', () async {
      await api.dio.get('/api/v1/notifications');
      return 'Service available';
    });

    // 10. Trash
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

    setState(() => _loading = false);
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
        if (idx >= 0)
          _checks[idx] = c.copyWith(status: _CheckStatus.pass, detail: detail);
      });
    } catch (e) {
      setState(() {
        final idx = _checks.indexWhere((ch) => ch.name == name);
        if (idx >= 0)
          _checks[idx] =
              c.copyWith(status: _CheckStatus.fail, detail: e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = _checks.where((c) => c.status == _CheckStatus.pass).length;
    final failed = _checks.where((c) => c.status == _CheckStatus.fail).length;
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

        // Summary card
        if (!_loading && _checks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: failed == 0
                  ? AppTheme.success.withOpacity(0.08)
                  : AppTheme.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: failed == 0
                      ? AppTheme.success.withOpacity(0.3)
                      : AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(failed == 0 ? Icons.verified_rounded : Icons.warning_rounded,
                  size: 36,
                  color: failed == 0 ? AppTheme.success : AppTheme.warning),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      failed == 0
                          ? 'All Systems Operational'
                          : '$failed issue${failed == 1 ? '' : 's'} detected',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: failed == 0
                              ? AppTheme.success
                              : AppTheme.warning),
                    ),
                    Text('$passed/$total checks passed',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted)),
                  ])),
            ]),
          ),
        const SizedBox(height: 24),

        // Checks list
        Container(
          decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border)),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border))),
              child: Row(children: [
                const Expanded(
                    flex: 3,
                    child: Text('Component',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted))),
                const Expanded(
                    flex: 4,
                    child: Text('Status',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted))),
                const SizedBox(
                    width: 24, child: Text('', style: TextStyle(fontSize: 12))),
              ]),
            ),
            ..._checks.map((c) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: AppTheme.border, width: 0.5))),
                  child: Row(children: [
                    Expanded(
                        flex: 3,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textPrimary)),
                              Text(c.description,
                                  style: const TextStyle(
                                      fontSize: 11, color: AppTheme.textMuted)),
                            ])),
                    Expanded(
                        flex: 4,
                        child: Text(
                          c.detail,
                          style: TextStyle(
                              fontSize: 12,
                              color: c.status == _CheckStatus.pass
                                  ? AppTheme.success
                                  : c.status == _CheckStatus.fail
                                      ? AppTheme.error
                                      : AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        )),
                    SizedBox(
                        width: 24,
                        child: Icon(
                          c.status == _CheckStatus.pass
                              ? Icons.check_circle_rounded
                              : c.status == _CheckStatus.fail
                                  ? Icons.cancel_rounded
                                  : Icons.hourglass_top_rounded,
                          size: 18,
                          color: c.status == _CheckStatus.pass
                              ? AppTheme.success
                              : c.status == _CheckStatus.fail
                                  ? AppTheme.error
                                  : AppTheme.textMuted,
                        )),
                  ]),
                )),
          ]),
        ),
      ]),
    );
  }
}

enum _CheckStatus { running, pass, fail }

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
