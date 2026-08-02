import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _systemStats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = getIt<ApiClient>();
      final usersResp = await api.dio.get('/api/v1/admin/users');
      final statsResp = await api.dio.get('/api/v1/admin/system');
      setState(() {
        _users = List<Map<String, dynamic>>.from(usersResp.data['users'] ?? []);
        _systemStats = statsResp.data;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Admin access denied or failed: $e'; _loading = false; });
    }
  }

  Future<void> _updateRole(String userId, String newRole) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.put('/api/v1/admin/users/role', data: {'user_id': userId, 'role': newRole});
      _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Role updated to $newRole')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.admin_panel_settings, size: 48, color: AppTheme.textMuted),
        const SizedBox(height: 16),
        Text(_error!, style: const TextStyle(color: AppTheme.textMuted)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
      ]));
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Admin Portal', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        Text('System management and user administration', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // System Stats Cards
        if (_systemStats != null) ...[
          Wrap(spacing: 16, runSpacing: 16, children: [
            _statCard('Users', '${_systemStats!['total_users']}', Icons.people_rounded),
            _statCard('Files', '${_systemStats!['total_files']}', Icons.insert_drive_file_rounded),
            _statCard('Storage', _formatBytes(_systemStats!['total_storage_bytes'] ?? 0), Icons.storage_rounded),
            _statCard('Shares', '${_systemStats!['total_active_shares']}', Icons.share_rounded),
            _statCard('Devices', '${_systemStats!['total_devices']}', Icons.devices_rounded),
            _statCard('Version', '${_systemStats!['version']}', Icons.info_rounded),
          ]),
          const SizedBox(height: 32),
        ],

        // Users Table
        Text('Users', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
          child: Column(children: _users.map((u) => ListTile(
            leading: CircleAvatar(
              backgroundColor: u['role'] == 'admin' ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.2),
              child: Icon(u['role'] == 'admin' ? Icons.shield_rounded : Icons.person_rounded,
                color: u['role'] == 'admin' ? Colors.white : AppTheme.textMuted, size: 20),
            ),
            title: Text(u['display_name'] ?? u['email'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('${u['email']} • ${u['role']}${u['totp_enabled'] == true ? ' • 🔐 MFA' : ''}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            trailing: PopupMenuButton<String>(
              onSelected: (role) => _updateRole(u['id'], role),
              itemBuilder: (_) => ['admin', 'user', 'viewer'].map((r) =>
                PopupMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
              child: Chip(label: Text(u['role'], style: const TextStyle(fontSize: 11)), backgroundColor: AppTheme.surface),
            ),
          )).toList()),
        ),
      ],
    ));
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      width: 160, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.primary, size: 24),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ]),
    );
  }

  String _formatBytes(dynamic bytes) {
    final b = (bytes is int) ? bytes : (bytes as num).toInt();
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(1)} GB';
  }
}
