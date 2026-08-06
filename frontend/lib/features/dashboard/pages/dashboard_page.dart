import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final api = getIt<ApiClient>();
      final response = await api.dio.get('/api/v1/analytics/overview');
      setState(() {
        _stats = response.data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load dashboard data';
        _stats = {
          'total_files': 0,
          'total_folders': 0,
          'total_size_bytes': 0,
          'total_devices': 0,
          'active_shares': 0,
          'total_backups': 0,
          'formatted_size': '0 B'
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Welcome Header
          Text('Welcome back',
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text("Here's an overview of your Personal Cloud",
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 32),

          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.warning_rounded,
                    color: AppTheme.warning, size: 18),
                const SizedBox(width: 8),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.warning, fontSize: 13))
              ]),
            ),

          // Stats Grid — live data
          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator()))
          else
            LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: cols,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StatCard(
                      icon: Icons.devices_rounded,
                      label: 'Connected Devices',
                      value: '${_stats['total_devices'] ?? 0}',
                      color: AppTheme.primary),
                  _StatCard(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'Total Files',
                      value: '${_stats['total_files'] ?? 0}',
                      color: AppTheme.accent),
                  _StatCard(
                      icon: Icons.storage_rounded,
                      label: 'Storage Used',
                      value: _stats['formatted_size'] ??
                          formatFileSize(_stats['total_size_bytes'] ?? 0),
                      color: AppTheme.success),
                  _StatCard(
                      icon: Icons.share_rounded,
                      label: 'Active Shares',
                      value: '${_stats['active_shares'] ?? 0}',
                      color: AppTheme.warning),
                ],
              );
            }),
          const SizedBox(height: 32),

          // Quick Actions
          Text('Quick Actions',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _ActionChip(
                icon: Icons.upload_file_rounded,
                label: 'Upload Files',
                onTap: () => context.go('/files')),
            _ActionChip(
                icon: Icons.folder_rounded,
                label: 'Browse Files',
                onTap: () => context.go('/files')),
            _ActionChip(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: () => context.go('/search')),
            _ActionChip(
                icon: Icons.devices_rounded,
                label: 'Manage Devices',
                onTap: () => context.go('/devices')),
            _ActionChip(
                icon: Icons.settings_rounded,
                label: 'Settings',
                onTap: () => context.go('/settings')),
            _ActionChip(
                icon: Icons.delete_outline_rounded,
                label: 'Trash',
                onTap: () => context.go('/trash')),
          ]),
          const SizedBox(height: 32),

          // System Info
          Text('System Status',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatusRow(
                  label: 'Total Folders',
                  value: '${_stats['total_folders'] ?? 0}'),
              Divider(color: AppTheme.borderColor(context), height: 24),
              _StatusRow(
                  label: 'Total Backups',
                  value: '${_stats['total_backups'] ?? 0}'),
              Divider(color: AppTheme.borderColor(context), height: 24),
              _StatusRow(
                  label: 'Server Status',
                  value: 'Online',
                  valueColor: AppTheme.success),
            ]),
          ),
          const SizedBox(height: 32),

          // Recent Files
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Recent Files',
                style: Theme.of(context).textTheme.headlineMedium),
            TextButton(
                onPressed: () => context.go('/files'),
                child: const Text('View all')),
          ]),
          const SizedBox(height: 12),
          _RecentFilesWidget(),
        ]),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatusRow({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: AppTheme.textMutedColor(context))),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimaryColor(context))),
      ]);
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor(context))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 20, color: color)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMutedColor(context))),
              ]),
            ]),
      );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(context))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimaryColor(context))),
            ]),
          ),
        ),
      );
}

class _RecentFilesWidget extends StatefulWidget {
  @override
  State<_RecentFilesWidget> createState() => _RecentFilesWidgetState();
}

class _RecentFilesWidgetState extends State<_RecentFilesWidget> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/files',
          queryParameters: {'limit': 5, 'sort': 'updated_at'});
      setState(() {
        _files = List<Map<String, dynamic>>.from(resp.data['entries'] ?? [])
            .where((e) => e['entry_type'] == 'file')
            .take(5)
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor(context))),
        child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_files.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor(context))),
        child: Center(
            child: Text('No recent files',
                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13))),
      );
    }
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderColor(context))),
      child: Column(
          children: _files
              .map((f) => ListTile(
                    leading: const Icon(Icons.insert_drive_file_rounded,
                        size: 20, color: AppTheme.primary),
                    title: Text(f['name'] ?? '',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textPrimaryColor(context)),
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatFileSize(f['size_bytes'] ?? 0),
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textMutedColor(context))),
                    dense: true,
                  ))
              .toList()),
    );
  }
}
