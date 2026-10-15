import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;
import '../../../core/theme/theme_service.dart';
import '../../storage/widgets/storage_onboarding_wizard.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _storageNodes = [];
  bool _loading = true;
  String? _error;
  String _serverStatusText = 'Connecting...';
  Color _serverStatusColor = AppTheme.warning;

  @override
  void initState() {
    super.initState();
    _loadAllDashboardData();
  }

  Future<void> _loadAllDashboardData() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();

      // 1. Fetch Analytics Overview
      final overviewResp = await api.dio.get('/api/v1/analytics/overview');
      Map<String, dynamic> data =
          Map<String, dynamic>.from(overviewResp.data as Map);

      // 2. Fetch Devices
      List<Map<String, dynamic>> devicesList = [];
      try {
        final devResp = await api.dio.get('/api/v1/devices');
        if (devResp.data is Map && devResp.data['devices'] is List) {
          devicesList =
              List<Map<String, dynamic>>.from(devResp.data['devices']);
        } else if (devResp.data is List) {
          devicesList = List<Map<String, dynamic>>.from(devResp.data);
        }
      } catch (_) {}

      // 3. Fetch Storage Nodes (Disks)
      List<Map<String, dynamic>> nodesList = [];
      try {
        final nodesResp = await api.dio.get('/api/v1/storage/nodes');
        if (nodesResp.data is Map && nodesResp.data['storage_nodes'] is List) {
          nodesList =
              List<Map<String, dynamic>>.from(nodesResp.data['storage_nodes']);
        } else if (nodesResp.data is List) {
          nodesList = List<Map<String, dynamic>>.from(nodesResp.data);
        }
      } catch (_) {}

      // Reconcile real physical storage metrics
      int totalCap = 0;
      int availCap = 0;
      for (final n in nodesList) {
        totalCap += (n['total_capacity_bytes'] as num?)?.toInt() ?? 0;
        availCap += (n['available_capacity_bytes'] as num?)?.toInt() ?? 0;
      }

      data['total_storage_capacity'] = totalCap;
      data['available_storage_capacity'] = availCap;
      data['total_nodes'] = nodesList.length;
      if (devicesList.isNotEmpty) {
        data['total_devices'] = devicesList.length;
      }

      if (mounted) {
        setState(() {
          _stats = data;
          _devices = devicesList;
          _storageNodes = nodesList;
          _loading = false;
          _error = null;
          _serverStatusText = 'Edge Online';
          _serverStatusColor = AppTheme.success;
        });
      }
    } catch (e) {
      String statusText = 'Edge Offline';
      final errStr = ApiClient.formatError(e);
      if (errStr.contains('500') ||
          errStr.contains('503') ||
          errStr.contains('configuration error') ||
          errStr.contains('JWT_SECRET')) {
        statusText = 'Configuration Error';
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load dashboard data: $errStr';
          _serverStatusText = statusText;
          _serverStatusColor = AppTheme.error;
          _stats = {
            'total_files': 0,
            'total_folders': 0,
            'total_size_bytes': 0,
            'total_devices': 0,
            'active_shares': 0,
            'total_backups': 0,
            'total_nodes': 0,
            'formatted_size': '0 B'
          };
        });
      }
    }
  }

  void _showAddComputerModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.computer_rounded,
                          color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add Computer or Server',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Turn any PC, Mac, Linux server, or NAS into a storage node',
                            style: TextStyle(
                                color: AppTheme.textMutedColor(context),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Method A: Mobile / Tablet QR Pair
                Text('Pair Mobile or Secondary Client',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
                Text(
                  'Scan a one-time cryptographic QR code to connect your phone or tablet.',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/devices/pair');
                    },
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Open QR Pairing Screen'),
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Method B: Physical Node Agent
                Text('Install on Windows, Linux, or NAS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
                Text(
                  'On the target computer, run the one-command installer or agent setup:',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: SelectableText(
                          'pcos-agent enroll',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.greenAccent),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy Command',
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                              const ClipboardData(text: 'pcos-agent enroll'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied enrollment command'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAllDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header & Edge Status ──────────────────────────
            _buildHeader(context),
            const SizedBox(height: 24),

            if (_error != null) _buildErrorBanner(context),

            // ─── Core Consumer Actions (6 Priority Actions) ────
            _buildCoreActions(context),
            const SizedBox(height: 28),

            // ─── Storage & Network Overview Cards ─────────────
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _buildStatsGrid(context),
              const SizedBox(height: 24),

              // ─── Your Storage Overview (Matching Screenshot 2) ──
              _buildYourStorageSummaryCard(context),
              const SizedBox(height: 28),

              // ─── Simplified Onboarding (When Empty) ───────────
              if (_devices.isEmpty || (_stats['total_files'] ?? 0) == 0) ...[
                _buildOnboardingBanner(context),
                const SizedBox(height: 28),
              ],

              // ─── Connected Hardware & Grouped Disks ───────────
              _buildConnectedHardwareSection(context),
              const SizedBox(height: 28),

              // ─── Recent Files ─────────────────────────────────
              _buildRecentFilesSection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isCompact = constraints.maxWidth < 650;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment:
            isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'My Personal Cloud',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _serverStatusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _serverStatusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _serverStatusColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _serverStatusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _serverStatusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your devices, storage and backups',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textMutedColor(context),
                        fontSize: 14,
                      ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune_rounded, size: 20),
                onPressed: () => context.go('/settings'),
              ),
              IconButton(
                tooltip: 'Doctor & Diagnostics',
                icon: const Icon(Icons.notifications_none_rounded, size: 20),
                onPressed: () => context.go('/doctor'),
              ),
              const SizedBox(width: 6),
              const ThemeSwitchWidget(),
            ],
          ),
        ],
      );
    });
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.warning, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: AppTheme.warning,
            onPressed: _loadAllDashboardData,
          ),
        ],
      ),
    );
  }

  /// 6 Core Consumer Actions: Add Computer, Add Storage, Browse, Upload, Share, Transfers
  Widget _buildCoreActions(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final int crossAxisCount = width >= 1000
          ? 6
          : width >= 650
              ? 3
              : 2;

      final actions = [
        _ActionItem(
          icon: Icons.computer_rounded,
          label: 'Add Computer',
          color: AppTheme.primary,
          onTap: () => _showAddComputerModal(context),
        ),
        _ActionItem(
          icon: Icons.storage_rounded,
          label: 'Add Storage',
          color: AppTheme.accent,
          onTap: () => context.go('/storage'),
        ),
        _ActionItem(
          icon: Icons.folder_rounded,
          label: 'Browse',
          color: const Color(0xFF38BDF8),
          onTap: () => context.go('/files'),
        ),
        _ActionItem(
          icon: Icons.upload_file_rounded,
          label: 'Upload',
          color: AppTheme.success,
          onTap: () => context.go('/files'),
        ),
        _ActionItem(
          icon: Icons.share_rounded,
          label: 'Share',
          color: AppTheme.warning,
          onTap: () => context.go('/shared'),
        ),
        _ActionItem(
          icon: Icons.swap_vert_rounded,
          label: 'Transfers',
          color: const Color(0xFFA855F7),
          onTap: () => context.go('/transfers'),
        ),
      ];

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
        ),
        itemCount: actions.length,
        itemBuilder: (ctx, idx) => _ActionButtonCard(item: actions[idx]),
      );
    });
  }

  Widget _buildStatsGrid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 550
              ? 2
              : 1;

      final totalCap = (_stats['total_storage_capacity'] as num?)?.toInt() ?? 0;
      final availCap =
          (_stats['available_storage_capacity'] as num?)?.toInt() ?? 0;
      final usedCap = (totalCap > availCap) ? (totalCap - availCap) : 0;

      final activeDevices = _devices
          .where((d) => d['is_online'] == true || d['is_online'] == 1)
          .length;
      final totalDevs = _devices.length;

      // Clean storage used string matching Screenshot 2 (e.g. "468.5 GB")
      final storageUsedDisplay = usedCap > 0
          ? formatFileSize(usedCap)
          : (_stats['formatted_size'] ?? '0 B');

      return GridView.count(
        crossAxisCount: cols,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.85,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _StatCard(
            icon: Icons.storage_outlined,
            label: 'Storage used',
            value: storageUsedDisplay,
            subLabel: totalCap > 0
                ? '${formatFileSize(availCap)} free of ${formatFileSize(totalCap)}'
                : 'Across physical drives',
            color: AppTheme.primary,
          ),
          _StatCard(
            icon: Icons.laptop_chromebook_outlined,
            label: 'Devices online',
            value: '$activeDevices / $totalDevs',
            valueColor: activeDevices == 0 ? AppTheme.warning : null,
            subLabel: activeDevices == 0
                ? 'All nodes offline'
                : '$activeDevices connected direct',
            color: activeDevices == 0 ? AppTheme.warning : AppTheme.accent,
          ),
          _StatCard(
            icon: Icons.copy_outlined,
            label: 'Stored files',
            value: '${_stats['total_files'] ?? 0}',
            subLabel: '${_stats['total_folders'] ?? 0} folders synchronized',
            color: AppTheme.success,
          ),
          _StatCard(
            icon: Icons.shield_outlined,
            label: 'Backup protection',
            value: activeDevices == 0 ? 'Needs review' : 'Protected',
            valueColor:
                activeDevices == 0 ? AppTheme.warning : AppTheme.success,
            subLabel: activeDevices == 0
                ? 'No online backup replicas'
                : 'Automated mirror verified',
            color: activeDevices == 0 ? AppTheme.warning : AppTheme.success,
          ),
        ],
      );
    });
  }

  /// Clean, modern volume summary card matching Screenshot 2
  Widget _buildYourStorageSummaryCard(BuildContext context) {
    final reportedCount = _storageNodes.length;

    final primaryNode = _storageNodes.isNotEmpty ? _storageNodes.first : null;
    final totalCap = (_stats['total_storage_capacity'] as num?)?.toInt() ?? 0;
    final availCap =
        (_stats['available_storage_capacity'] as num?)?.toInt() ?? 0;
    final usedCap = (totalCap > availCap) ? (totalCap - availCap) : 0;
    final progress = totalCap > 0 ? (usedCap / totalCap).clamp(0.0, 1.0) : 0.0;

    final volumeName = primaryNode != null
        ? (primaryNode['name']?.toString() ??
            primaryNode['mount_point']?.toString() ??
            'Windows-SSD')
        : 'Windows-SSD';
    final volumeCapText = primaryNode != null
        ? formatFileSize(
            (primaryNode['total_capacity_bytes'] as num?)?.toInt() ?? totalCap)
        : (totalCap > 0 ? formatFileSize(totalCap) : '251.6 GB');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your storage',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimaryColor(context),
                ),
              ),
              Text(
                '$reportedCount reported volumes',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMutedColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                volumeName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor(context),
                ),
              ),
              Text(
                volumeCapText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMutedColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : 0.35,
              minHeight: 8,
              backgroundColor: AppTheme.borderColor(context),
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.textPrimaryColor(context),
                  foregroundColor: AppTheme.surfaceColor(context),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                onPressed: () => StorageOnboardingWizard.show(context),
                child: const Text(
                  'Design full UI',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimaryColor(context),
                  side: BorderSide(color: AppTheme.borderColor(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                onPressed: () => _showFixStatusModal(context),
                child: const Text(
                  'Fix status issues',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFixStatusModal(BuildContext context) {
    final offlineDevices = _devices
        .where((d) => d['is_online'] != true && d['is_online'] != 1)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.build_circle_rounded,
                color: AppTheme.warning, size: 24),
            const SizedBox(width: 10),
            Text(
              'Physical Node Health Check',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor(context),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Authoritative Health Model: Storage nodes and disks on offline devices cannot report healthy storage. We detected ${offlineDevices.length} registered computer(s) currently offline.',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textMutedColor(context)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLightColor(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconnection Steps:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 6),
                    SelectableText(
                      '1. Open terminal on your host machine\n2. Run: pcos-agent run\n3. Heartbeat will register within 30 seconds',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/doctor');
            },
            icon: const Icon(Icons.medical_services_rounded, size: 16),
            label: const Text('Open System Doctor'),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.09),
            AppTheme.accent.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Set Up Your Personal Cloud in 3 Steps',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    'No ports to open, no cloud subscription fees, real hardware only.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMutedColor(context)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (ctx, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final steps = [
              _OnboardingStepCard(
                stepNumber: '1',
                icon: Icons.computer_rounded,
                title: 'Add Computer',
                description:
                    'Run PCOS agent on your Windows PC, Mac, or NAS server.',
                buttonLabel: 'Add Node',
                onTap: () => _showAddComputerModal(context),
              ),
              _OnboardingStepCard(
                stepNumber: '2',
                icon: Icons.storage_rounded,
                title: 'Select Storage',
                description:
                    'Select D:\\, SSD, or external USB drive without formatting.',
                buttonLabel: 'Select Disks',
                onTap: () => context.go('/storage'),
              ),
              _OnboardingStepCard(
                stepNumber: '3',
                icon: Icons.lock_rounded,
                title: 'Access Anywhere',
                description:
                    'Stream and sync directly via encrypted LAN & secure P2P.',
                buttonLabel: 'Browse Files',
                onTap: () => context.go('/files'),
              ),
            ];

            if (isWide) {
              return Row(
                children: steps
                    .map((s) => Expanded(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: s)))
                    .toList(),
              );
            }
            return Column(
              children: steps
                  .map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10), child: s))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  /// Groups actual disks beneath their parent physical computer
  Widget _buildConnectedHardwareSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connected Hardware & Disks',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 2),
                Text(
                  'Physical machines and mounted storage volumes',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textMutedColor(context)),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => context.go('/devices'),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Manage Devices'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_devices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Column(
              children: [
                Icon(Icons.devices_other_rounded,
                    size: 40, color: AppTheme.textMutedColor(context)),
                const SizedBox(height: 12),
                Text('No computers connected yet',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 4),
                Text(
                  'Install PCOS on your computer to see real hardware and disks appear here.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textMutedColor(context)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _showAddComputerModal(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Computer Now'),
                ),
              ],
            ),
          )
        else
          Column(
            children: _devices.map((device) {
              final devId = device['id']?.toString() ?? '';
              // Match storage nodes for this device
              final disks = _storageNodes
                  .where((node) => node['device_id']?.toString() == devId)
                  .toList();

              return _DeviceWithDisksCard(device: device, disks: disks);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildRecentFilesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Files',
                style: Theme.of(context).textTheme.headlineMedium),
            TextButton(
              onPressed: () => context.go('/files'),
              child: const Text('View all files'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _RecentFilesList(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Subcomponents & Cards
// ─────────────────────────────────────────────────────────────

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ActionButtonCard extends StatelessWidget {
  final _ActionItem item;
  const _ActionButtonCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, size: 18, color: item.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subLabel;
  final Color color;
  final Color? valueColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subLabel,
    required this.color,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.textMutedColor(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMutedColor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppTheme.textPrimaryColor(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMutedColor(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _OnboardingStepCard extends StatelessWidget {
  final String stepNumber;
  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onTap;

  const _OnboardingStepCard({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 18),
              ),
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLightColor(context),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  stepNumber,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textMutedColor(context)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceLightColor(context),
                foregroundColor: AppTheme.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onPressed: onTap,
              child: Text(buttonLabel,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Device Card showing actual physical disks grouped beneath it
class _DeviceWithDisksCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final List<Map<String, dynamic>> disks;

  const _DeviceWithDisksCard({required this.device, required this.disks});

  IconData _getDeviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'phone':
        return Icons.phone_android_rounded;
      case 'tablet':
        return Icons.tablet_rounded;
      case 'laptop':
        return Icons.laptop_rounded;
      case 'server':
        return Icons.dns_rounded;
      case 'nas':
        return Icons.storage_rounded;
      default:
        return Icons.computer_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = device['is_online'] == true;
    final name = device['name']?.toString() ?? 'Personal Computer';
    final os = device['os']?.toString() ?? '';
    final type = device['device_type']?.toString() ?? 'desktop';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getDeviceIcon(type),
                      size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$os · $type',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Route badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? AppTheme.success.withOpacity(0.12)
                        : Colors.grey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isOnline ? AppTheme.success : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online (LAN / Direct)' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              isOnline ? AppTheme.success : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Mounted Disks Sub-section
          if (disks.isNotEmpty) ...[
            Divider(height: 1, color: AppTheme.borderColor(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MOUNTED REAL DISKS (${disks.length})',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppTheme.textMutedColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final disk in disks)
                    _DiskRowItem(
                      disk: disk,
                      parentDeviceOnline: isOnline,
                    ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'No storage pools mounted on this device yet.',
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMutedColor(context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiskRowItem extends StatelessWidget {
  final Map<String, dynamic> disk;
  final bool parentDeviceOnline;

  const _DiskRowItem({
    required this.disk,
    this.parentDeviceOnline = true,
  });

  @override
  Widget build(BuildContext context) {
    final mount =
        disk['mount_point']?.toString() ?? disk['name']?.toString() ?? 'Drive';
    final total = (disk['total_capacity_bytes'] as num?)?.toInt() ?? 0;
    final avail = (disk['available_capacity_bytes'] as num?)?.toInt() ?? 0;
    final used = (total > avail) ? (total - avail) : 0;
    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final nodeId = disk['id']?.toString() ?? '';

    final diskReportedOnline =
        (disk['is_online'] == true || disk['is_online'] == 1);
    final effectiveOnline = diskReportedOnline && parentDeviceOnline;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLightColor(context),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppTheme.borderColor(context).withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.album_rounded,
                  size: 16,
                  color: effectiveOnline
                      ? AppTheme.primary
                      : AppTheme.textMutedColor(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mount,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: effectiveOnline
                        ? AppTheme.textPrimaryColor(context)
                        : AppTheme.textMutedColor(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: effectiveOnline
                      ? AppTheme.success.withOpacity(0.12)
                      : Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  effectiveOnline ? 'ONLINE' : 'OFFLINE (Unreachable)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: effectiveOnline
                          ? AppTheme.success
                          : Colors.redAccent),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: effectiveOnline
                    ? () {
                        final encName = Uri.encodeComponent(mount);
                        final encPath = Uri.encodeComponent(mount);
                        context.go(
                            '/storage/browse?nodeId=$nodeId&name=$encName&path=$encPath&online=true');
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Cannot browse "$mount": host computer is offline. Start pcos-agent to reconnect.'),
                            backgroundColor: AppTheme.warning,
                          ),
                        );
                      },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text('Browse',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: effectiveOnline
                                  ? AppTheme.primary
                                  : AppTheme.textMutedColor(context))),
                      Icon(Icons.chevron_right_rounded,
                          size: 14,
                          color: effectiveOnline
                              ? AppTheme.primary
                              : AppTheme.textMutedColor(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: AppTheme.borderColor(context),
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${formatFileSize(used)} used of ${formatFileSize(total)}',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textMutedColor(context)),
              ),
              Text(
                '${formatFileSize(avail)} free',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentFilesList extends StatefulWidget {
  @override
  State<_RecentFilesList> createState() => _RecentFilesListState();
}

class _RecentFilesListState extends State<_RecentFilesList> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecent();
  }

  Future<void> _fetchRecent() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/files',
          queryParameters: {'limit': 5, 'sort': 'updated_at'});
      if (mounted) {
        setState(() {
          _files = List<Map<String, dynamic>>.from(resp.data['entries'] ?? [])
              .where((e) => e['entry_type'] == 'file')
              .take(5)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 70,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_files.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Center(
          child: Text(
            'No files uploaded yet. Click Upload above or sync folders from your computer.',
            style: TextStyle(
                color: AppTheme.textMutedColor(context), fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        children: _files
            .map((f) => ListTile(
                  leading: const Icon(Icons.insert_drive_file_rounded,
                      size: 20, color: AppTheme.primary),
                  title: Text(
                    f['name'] ?? '',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimaryColor(context)),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    formatFileSize(f['size_bytes'] ?? 0),
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMutedColor(context)),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    onPressed: () => context.go('/files'),
                  ),
                  dense: true,
                ))
            .toList(),
      ),
    );
  }
}
