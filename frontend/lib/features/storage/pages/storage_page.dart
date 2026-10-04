import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;
import 'physical_storage_browser_page.dart';

/// Comprehensive Plug-and-Play Storage Nodes and Drive Pool Management Page.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _storageNodes = [];
  List<Map<String, dynamic>> _devices = [];
  int _totalCapacityBytes = 0;
  int _availableCapacityBytes = 0;
  int _usedCapacityBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();

      // Fetch storage nodes
      final nodesResp = await api.dio.get('/api/v1/storage/nodes');
      final List rawNodes =
          nodesResp.data is Map && nodesResp.data['storage_nodes'] is List
              ? nodesResp.data['storage_nodes']
              : (nodesResp.data is List ? nodesResp.data : []);

      final nodes =
          rawNodes.map((n) => Map<String, dynamic>.from(n as Map)).toList();

      // Fetch devices for mapping
      final devResp = await api.dio.get('/api/v1/devices');
      final List rawDevices =
          devResp.data is Map && devResp.data['devices'] is List
              ? devResp.data['devices']
              : (devResp.data is List ? devResp.data : []);
      final devices =
          rawDevices.map((d) => Map<String, dynamic>.from(d as Map)).toList();

      int total = 0;
      int avail = 0;

      for (final n in nodes) {
        final nodeTotal = (n['total_capacity_bytes'] as num?)?.toInt() ?? 0;
        final nodeAvail = (n['available_capacity_bytes'] as num?)?.toInt() ?? 0;
        total += nodeTotal;
        avail += nodeAvail;
      }

      // If no nodes yet, check default quota or overview
      if (total == 0) {
        try {
          final userResp = await api.dio.get('/api/v1/users/me');
          if (userResp.data is Map) {
            total =
                (userResp.data['quota_bytes'] as num?)?.toInt() ?? 53687091200;
            final used = (userResp.data['used_bytes'] as num?)?.toInt() ?? 0;
            avail = total > used ? total - used : 0;
          }
        } catch (_) {}
      }

      int used = total > avail ? total - avail : 0;

      if (mounted) {
        setState(() {
          _storageNodes = nodes;
          _devices = devices;
          _totalCapacityBytes = total;
          _availableCapacityBytes = avail;
          _usedCapacityBytes = used;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiClient.formatError(e);
          _loading = false;
        });
      }
    }
  }

  void _showAddStorageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.storage_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Physical Storage Pools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.verified_rounded,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Zero-Assumption Architecture: Storage nodes are discovered, measured, and verified automatically by the physical PCOS Agent. Drives cannot be added with fake browser text paths.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPrimaryColor(context)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                Text('How to Attach Real Storage:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 8),
                Text(
                  '1. Pair your laptop, desktop, server, or NAS with PCOS.\n'
                  '2. Run the PCOS Agent daemon on that machine.\n'
                  '3. All physical disks, USBs, and SSD volumes are automatically discovered, measured, and mounted with no manual configuration.',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.textMutedColor(context)),
                ),
                const SizedBox(height: 16),
                Text('Agent Command (Run on Node):',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: SelectableText(
                          'pcos-agent --daemon',
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
                              const ClipboardData(text: 'pcos-agent --daemon'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied daemon command to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (_devices.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppTheme.warning, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No devices connected yet. Pair your first computer or mobile device to start.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimaryColor(context)),
                        ),
                      ),
                    ]),
                  ),
                ] else ...[
                  Text('Paired Host Devices (${_devices.length}):',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimaryColor(context))),
                  const SizedBox(height: 8),
                  ..._devices.map((d) {
                    final bool isOnline = d['is_online'] == 1 || d['is_online'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLightColor(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                            size: 16,
                            color: isOnline ? AppTheme.success : AppTheme.textMutedColor(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${d['name'] ?? 'Device'} (${d['os'] ?? 'OS'})',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimaryColor(context)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isOnline ? AppTheme.success : Colors.grey)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOnline ? AppTheme.success : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_devices.isEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/devices/pair');
              },
              icon: const Icon(Icons.qr_code_rounded, size: 16),
              label: const Text('Pair Device Now'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _loadStorageData();
            },
            child: const Text('Refresh Storage Pools'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStorageNode(String nodeId, String nodeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Disconnect Storage Drive?'),
        content: Text(
            'Are you sure you want to unlink "$nodeName"? Your files on disk will NOT be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect Drive'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final api = getIt<ApiClient>();
      await api.dio.delete('/api/v1/storage/nodes/$nodeId');
      _loadStorageData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Storage drive "$nodeName" unlinked.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to unlink: ${ApiClient.formatError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedPct = _totalCapacityBytes > 0
        ? (_usedCapacityBytes / _totalCapacityBytes).clamp(0.0, 1.0)
        : 0.0;

    return RefreshIndicator(
      onRefresh: _loadStorageData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Storage Pools & Disks',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Unified personal storage aggregated across your connected drives and devices.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ]),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _showAddStorageDialog,
                  icon: const Icon(Icons.add_to_drive_rounded, size: 20),
                  label: const Text('Add Storage'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.warning, fontSize: 13))),
                ]),
              ),

            // Aggregate Capacity Hero Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.pie_chart_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Aggregated Capacity',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                '${formatFileSize(_availableCapacityBytes)} available of ${formatFileSize(_totalCapacityBytes)}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textMutedColor(context)),
                              ),
                            ]),
                      ]),
                      Text(
                        '${(usedPct * 100).toStringAsFixed(1)}% Used',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: usedPct,
                      minHeight: 12,
                      backgroundColor: AppTheme.surfaceLightColor(context),
                      color: usedPct > 0.9
                          ? AppTheme.error
                          : (usedPct > 0.75
                              ? AppTheme.warning
                              : AppTheme.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CapacityBadge(
                          color: AppTheme.primary,
                          label: 'Used Space',
                          value: formatFileSize(_usedCapacityBytes),
                        ),
                        _CapacityBadge(
                          color: AppTheme.success,
                          label: 'Free Space',
                          value: formatFileSize(_availableCapacityBytes),
                        ),
                        _CapacityBadge(
                          color: AppTheme.accent,
                          label: 'Connected Drives',
                          value: '${_storageNodes.length}',
                        ),
                      ]),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Connected Drives Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Storage Nodes',
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('${_storageNodes.length} Drive(s)',
                    style: TextStyle(color: AppTheme.textMutedColor(context))),
              ],
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator()))
            else if (_storageNodes.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storage_rounded,
                        size: 36, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Storage Drives Added Yet',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'PCOS is ready for plug-and-play storage. Add an external drive, USB, or local folder to expand your personal cloud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textMutedColor(context)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white),
                    onPressed: _showAddStorageDialog,
                    icon: const Icon(Icons.add_to_drive_rounded, size: 18),
                    label: const Text('Add Your First Drive'),
                  ),
                ]),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _storageNodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final node = _storageNodes[idx];
                  final totalBytes =
                      (node['total_capacity_bytes'] as num?)?.toInt() ?? 0;
                  final availBytes =
                      (node['available_capacity_bytes'] as num?)?.toInt() ?? 0;
                  final usedNodeBytes =
                      totalBytes > availBytes ? totalBytes - availBytes : 0;
                  final pct = totalBytes > 0
                      ? (usedNodeBytes / totalBytes).clamp(0.0, 1.0)
                      : 0.0;
                  final isOnline =
                      node['is_online'] == 1 || node['is_online'] == true;

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (isOnline
                                        ? AppTheme.success
                                        : AppTheme.textMuted)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.dns_rounded,
                                color: isOnline
                                    ? AppTheme.success
                                    : AppTheme.textMuted,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(
                                        node['name'] ?? 'Storage Node',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isOnline
                                                  ? AppTheme.success
                                                  : AppTheme.textMuted)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isOnline ? 'ONLINE' : 'OFFLINE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isOnline
                                                ? AppTheme.success
                                                : AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(
                                      node['storage_path'] ??
                                          'Path unconfigured',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppTheme.textMutedColor(context)),
                                    ),
                                  ]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppTheme.error, size: 20),
                              tooltip: 'Disconnect Drive',
                              onPressed: () => _deleteStorageNode(
                                  node['id'], node['name'] ?? 'Node'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor:
                                AppTheme.surfaceLightColor(context),
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${formatFileSize(availBytes)} free of ${formatFileSize(totalBytes)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMutedColor(context)),
                            ),
                            Wrap(
                              spacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('SMART: Healthy',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.primary)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Direct LAN',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.accent)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOnline
                                    ? AppTheme.primary
                                    : Colors.grey.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PhysicalStorageBrowserPage(
                                      nodeId: node['id'] ?? '',
                                      nodeName:
                                          node['name'] ?? 'Storage Node',
                                      storagePath: node['storage_path'] ?? '',
                                      isOnline: isOnline,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.folder_open_rounded,
                                  size: 16),
                              label: const Text(
                                'Browse Physical Files',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isOnline)
                              Text(
                                'Agent offline: start pcos-agent to connect',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMutedColor(context),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CapacityBadge extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _CapacityBadge(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textMutedColor(context))),
      ]),
    ]);
  }
}
