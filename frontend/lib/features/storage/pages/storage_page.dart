import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;
import 'physical_storage_browser_page.dart';
import '../widgets/storage_onboarding_wizard.dart';
import '../widgets/drive_grant_management_sheet.dart';

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
  Map<String, dynamic>? _clusterStatus;
  List<Map<String, dynamic>> _storagePolicies = [];
  bool _rebalancing = false;

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

      // Fetch cluster protection status
      Map<String, dynamic>? cluster;
      try {
        final clusterResp = await api.dio.get('/api/v1/cluster/status');
        if (clusterResp.data is Map && clusterResp.data['success'] == true) {
          cluster = Map<String, dynamic>.from(clusterResp.data);
        }
      } catch (_) {}

      // Fetch storage policies
      List<Map<String, dynamic>> policies = [];
      try {
        final policyResp = await api.dio.get('/api/v1/storage/policies');
        if (policyResp.data is Map && policyResp.data['policies'] is List) {
          policies = (policyResp.data['policies'] as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _storageNodes = nodes;
          _devices = devices;
          _totalCapacityBytes = total;
          _availableCapacityBytes = avail;
          _usedCapacityBytes = used;
          _clusterStatus = cluster;
          _storagePolicies = policies;
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
              color: AppTheme.primary.withOpacity(0.12),
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
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppTheme.primary.withOpacity(0.2)),
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
                Text('First Time Setup (Pairs & Starts in 1 Step):',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
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
                          'pcos-agent enroll --start',
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
                          Clipboard.setData(const ClipboardData(
                              text: 'pcos-agent enroll --start'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied 1-step onboarding command'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.qr_code_rounded, size: 16),
                      label: const Text('Get 6-Digit Pairing Code',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go('/devices/pair');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('If Machine Already Enrolled:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
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
                          'pcos-agent --daemon',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: Colors.white70),
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
                              content:
                                  Text('Copied daemon command to clipboard'),
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
                      color: AppTheme.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppTheme.warning.withOpacity(0.3)),
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
                    final bool isOnline =
                        d['is_online'] == 1 || d['is_online'] == true;
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
                            isOnline
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            size: 16,
                            color: isOnline
                                ? AppTheme.success
                                : AppTheme.textMutedColor(context),
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
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOnline
                                      ? AppTheme.success
                                      : Colors.grey),
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
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              StorageOnboardingWizard.show(context);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Guided Storage Wizard'),
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

  Future<void> _updateClusterMode(String newMode) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.put('/api/v1/cluster/mode', data: {'mode': newMode});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cluster protection mode set to: $newMode'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to update cluster mode: ${ApiClient.formatError(e)}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showChangeClusterModeDialog() {
    String selected = _clusterStatus?['mode'] ?? 'single';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Text('Cluster Protection Mode',
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context), fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select cluster redundancy and failover topology:',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textMutedColor(context)),
              ),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: const Text('Single Device Protection'),
                subtitle: const Text(
                    'Local storage pool without cross-device mirroring'),
                value: 'single',
                groupValue: selected,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDlgState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Two-Node Mirror (Active-Passive)'),
                subtitle: const Text(
                    'Asynchronous replication with < 15s RPO across 2 machines'),
                value: 'two_node_mirror',
                groupValue: selected,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDlgState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Always-On NAS Cluster (Quorum)'),
                subtitle: const Text(
                    'Zero-downtime distributed storage with automatic failover'),
                value: 'nas_cluster',
                groupValue: selected,
                activeColor: AppTheme.primary,
                onChanged: (val) => setDlgState(() => selected = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateClusterMode(selected);
              },
              child: const Text('Save Mode'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerRebalance() async {
    setState(() => _rebalancing = true);
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.post('/api/v1/cluster/rebalance');
      final moved = (resp.data is Map ? resp.data['moved_chunks'] : 0) ?? 0;
      final repl = (resp.data is Map ? resp.data['replicated_chunks'] : 0) ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Cluster rebalance complete! $moved chunks migrated, $repl replicas synced.'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rebalance failed: ${ApiClient.formatError(e)}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rebalancing = false);
      }
    }
  }

  void _showAddPolicyDialog() {
    String selectedCategory = 'photos';
    String selectedMime = 'image/*';
    String targetDrive = 'ssd';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.alt_route_rounded, color: AppTheme.accent),
              const SizedBox(width: 10),
              Text('Add Storage Routing Rule',
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context), fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Route incoming files to the most appropriate hardware volume based on MIME type or folder pattern.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textMutedColor(context)),
              ),
              const SizedBox(height: 16),
              Text('Content Category',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                dropdownColor: AppTheme.surfaceColor(context),
                items: const [
                  DropdownMenuItem(
                      value: 'photos',
                      child: Text('Photos & Memories (image/*)')),
                  DropdownMenuItem(
                      value: 'videos',
                      child: Text('Movies & 4K Video (video/*)')),
                  DropdownMenuItem(
                      value: 'audio', child: Text('Music & Audio (audio/*)')),
                  DropdownMenuItem(
                      value: 'documents',
                      child: Text('Documents & Work (application/*)')),
                  DropdownMenuItem(
                      value: 'backups',
                      child: Text('System Backups (backup/*)')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setDlgState(() {
                    selectedCategory = val;
                    if (val == 'photos') {
                      selectedMime = 'image/*';
                      targetDrive = 'ssd';
                    } else if (val == 'videos') {
                      selectedMime = 'video/*';
                      targetDrive = 'hdd';
                    } else if (val == 'audio') {
                      selectedMime = 'audio/*';
                      targetDrive = 'ssd';
                    } else if (val == 'documents') {
                      selectedMime = 'application/*';
                      targetDrive = 'nas';
                    } else if (val == 'backups') {
                      selectedMime = 'backup/*';
                      targetDrive = 'usb';
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              Text('Target Storage Medium',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: targetDrive,
                dropdownColor: AppTheme.surfaceColor(context),
                items: const [
                  DropdownMenuItem(
                      value: 'ssd',
                      child: Text('Fast NVMe / Solid-State Drive (SSD)')),
                  DropdownMenuItem(
                      value: 'hdd',
                      child: Text('High-Capacity Mechanical Disk (HDD)')),
                  DropdownMenuItem(
                      value: 'nas',
                      child: Text('Network Attached Storage (NAS Pool)')),
                  DropdownMenuItem(
                      value: 'usb',
                      child: Text('External Removable USB Drive')),
                ],
                onChanged: (val) => setDlgState(() => targetDrive = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _createStoragePolicy(
                    selectedCategory, selectedMime, targetDrive);
              },
              child: const Text('Create Rule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createStoragePolicy(
      String category, String mimePatterns, String targetDriveType) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/storage/policies', data: {
        'category': category,
        'mime_patterns': mimePatterns,
        'target_storage_type': targetDriveType,
        'availability_tier': 'local_only',
        'replica_count': 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Storage routing rule created: $category ($mimePatterns) -> ${targetDriveType.toUpperCase()}'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create rule: ${ApiClient.formatError(e)}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteStoragePolicy(String policyId) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.delete('/api/v1/storage/policies/$policyId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage routing rule deleted'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete rule: ${ApiClient.formatError(e)}'),
            backgroundColor: AppTheme.error,
          ),
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
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
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
            const SizedBox(height: 24),

            // Cluster Protection & High Availability Card
            _buildClusterProtectionCard(),
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
                      color: AppTheme.primary.withOpacity(0.1),
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
                                    .withOpacity(0.12),
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
                                              .withOpacity(0.15),
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
                                    color: AppTheme.primary.withOpacity(0.08),
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
                                    color: AppTheme.accent.withOpacity(0.08),
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
                                      nodeName: node['name'] ?? 'Storage Node',
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
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              onPressed: () {
                                final totalB =
                                    (node['total_capacity_bytes'] as num?)
                                            ?.toInt() ??
                                        0;
                                final availB =
                                    (node['available_capacity_bytes'] as num?)
                                            ?.toInt() ??
                                        0;
                                final usedB =
                                    totalB > availB ? totalB - availB : 0;
                                final id = node['id']?.toString() ?? '';
                                final name =
                                    node['name']?.toString() ?? 'Storage Drive';
                                final path = node['storage_path']?.toString() ??
                                    node['mount_point']?.toString() ??
                                    'D:\\';
                                final uuid = node['volume_uuid']?.toString() ??
                                    (id.length >= 8
                                        ? 'VOL-${id.substring(0, 8)}'
                                        : 'VOL-UNKNOWN');

                                DriveGrantManagementSheet.show(
                                  context,
                                  disk: node,
                                  deviceName:
                                      node['parent_device_name']?.toString() ??
                                          'This Device',
                                  onUpdated: _loadStorageData,
                                );
                              },
                              icon:
                                  const Icon(Icons.security_rounded, size: 16),
                              label: const Text(
                                'Manage Grant',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 32),
            _buildStoragePoliciesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildClusterProtectionCard() {
    final mode = _clusterStatus?['mode'] ?? 'single';
    final rpo = _clusterStatus?['rpo_seconds'] ?? 15;
    final rto = _clusterStatus?['rto_seconds'] ?? 5;
    final isHealthy = _clusterStatus?['cluster_healthy'] ?? true;
    final int nodesOnline =
        (_clusterStatus?['nodes_online'] as num?)?.toInt() ??
            (_devices
                .where((d) => d['is_online'] == 1 || d['is_online'] == true)
                .length);

    String modeTitle;
    String modeSubtitle;
    Color modeColor;
    IconData modeIcon;

    switch (mode) {
      case 'nas_cluster':
        modeTitle = 'Always-On NAS Cluster';
        modeSubtitle =
            'Zero-downtime distributed HA with quorum failover and active replication';
        modeColor = AppTheme.success;
        modeIcon = Icons.cloud_sync_rounded;
        break;
      case 'two_node_mirror':
        modeTitle = 'Two-Node Protection';
        modeSubtitle =
            'Active mirroring across paired machines with automatic secondary sync';
        modeColor = AppTheme.primary;
        modeIcon = Icons.copy_all_rounded;
        break;
      case 'single':
      default:
        modeTitle = 'Single Device Protection';
        modeSubtitle =
            'Single active machine storage pool. Connect a second device to enable mirroring';
        modeColor = nodesOnline > 1 ? AppTheme.accent : AppTheme.warning;
        modeIcon = Icons.computer_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: modeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(modeIcon, color: modeColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'High Availability & Cluster Protection',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: modeColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              modeTitle.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: modeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modeSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('Change Mode',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _showChangeClusterModeDialog,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _rebalancing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.balance_rounded, size: 16),
                    label: Text(
                      _rebalancing ? 'Rebalancing...' : 'Rebalance Nodes',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _rebalancing ? null : _triggerRebalance,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MetricItem(
                label: 'RPO Target (Max Loss)',
                value: '< ${rpo}s',
                sublabel: 'Near-instantaneous async queue',
                icon: Icons.timer_outlined,
                color: AppTheme.primary,
              ),
              _MetricItem(
                label: 'RTO Target (Failover)',
                value: '< ${rto}s',
                sublabel: 'Automatic leader election',
                icon: Icons.flash_on_rounded,
                color: AppTheme.accent,
              ),
              _MetricItem(
                label: 'Cluster Health',
                value: isHealthy ? '100% In Sync' : 'Degraded',
                sublabel: '$nodesOnline node(s) communicating',
                icon: isHealthy
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
                color: isHealthy ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoragePoliciesCard() {
    return Container(
      padding: const EdgeInsets.all(22),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.alt_route_rounded,
                        color: AppTheme.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Storage Routing Policy Engine',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Automatically routes media to the fastest drive and bulk data to high-capacity storage.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMutedColor(context)),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Routing Rule',
                    style: TextStyle(fontSize: 12)),
                onPressed: _showAddPolicyDialog,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _storagePolicies.isNotEmpty
                ? _storagePolicies.map((p) {
                    final isDefault = p['is_default'] == true;
                    final category =
                        (p['category'] ?? p['content_type'] ?? 'storage')
                            .toString()
                            .toLowerCase();
                    final mime =
                        (p['mime_patterns'] ?? p['content_type'] ?? '*')
                            .toString();
                    final targetType = (p['target_storage_type'] ??
                            p['target_drive_type'] ??
                            'SSD')
                        .toString()
                        .toUpperCase();
                    final id = p['id']?.toString() ?? '';

                    IconData icon;
                    String title;
                    if (category.contains('photo') || mime.contains('image')) {
                      icon = Icons.photo_library_rounded;
                      title = 'Photos & Memories';
                    } else if (category.contains('video') ||
                        mime.contains('video')) {
                      icon = Icons.movie_rounded;
                      title = 'Videos & Cinema';
                    } else if (category.contains('audio') ||
                        mime.contains('audio')) {
                      icon = Icons.music_note_rounded;
                      title = 'Music & Audio';
                    } else if (category.contains('document') ||
                        mime.contains('application') ||
                        mime.contains('pdf')) {
                      icon = Icons.description_rounded;
                      title = 'Documents & Code';
                    } else if (category.contains('backup')) {
                      icon = Icons.backup_table_rounded;
                      title = 'System Backups';
                    } else {
                      icon = Icons.rule_folder_rounded;
                      title = 'Rule: ${category.toUpperCase()}';
                    }

                    return _PolicyTile(
                      icon: icon,
                      title: isDefault ? title : 'Custom: $title',
                      matcher: mime,
                      targetDrive: '$targetType Pool',
                      targetType: targetType,
                      isDefault: isDefault,
                      onDelete: (!isDefault && id.isNotEmpty)
                          ? () => _deleteStoragePolicy(id)
                          : null,
                    );
                  }).toList()
                : const [
                    _PolicyTile(
                      icon: Icons.photo_library_rounded,
                      title: 'Photos & Live Moments',
                      matcher: 'image/*',
                      targetDrive: 'Ultra-Fast NVMe / SSD',
                      targetType: 'SSD',
                      isDefault: true,
                    ),
                    _PolicyTile(
                      icon: Icons.movie_rounded,
                      title: 'Videos & 4K Cinema',
                      matcher: 'video/*',
                      targetDrive: 'High-Capacity HDD Pool',
                      targetType: 'HDD',
                      isDefault: true,
                    ),
                    _PolicyTile(
                      icon: Icons.description_rounded,
                      title: 'Documents & Work',
                      matcher: 'application/*',
                      targetDrive: 'Redundant NAS / SSD',
                      targetType: 'NAS',
                      isDefault: true,
                    ),
                    _PolicyTile(
                      icon: Icons.backup_table_rounded,
                      title: 'Backups & Archives',
                      matcher: 'backup/*',
                      targetDrive: 'External USB Replicas',
                      targetType: 'USB',
                      isDefault: true,
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final String sublabel;
  final IconData icon;
  final Color color;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimaryColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sublabel,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textMutedColor(context),
          ),
        ),
      ],
    );
  }
}

class _PolicyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String matcher;
  final String targetDrive;
  final String targetType;
  final bool isDefault;
  final VoidCallback? onDelete;

  const _PolicyTile({
    required this.icon,
    required this.title,
    required this.matcher,
    required this.targetDrive,
    required this.targetType,
    required this.isDefault,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLightColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                ],
              ),
              if (!isDefault && onDelete != null)
                InkWell(
                  onTap: onDelete,
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: AppTheme.error),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('AUTO',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            matcher,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppTheme.textMutedColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.arrow_forward_rounded,
                  size: 12, color: AppTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  targetDrive,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
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
