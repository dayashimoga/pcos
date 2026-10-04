import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/device_bloc.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<DeviceBloc>()..add(const DevicesLoadRequested()),
      child: const _DevicesContent(),
    );
  }
}

class _DevicesContent extends StatelessWidget {
  const _DevicesContent();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (state is DeviceActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.success),
          );
        } else if (state is DeviceError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(state.message), backgroundColor: AppTheme.error),
          );
        }
      },
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Devices',
                          style: Theme.of(context).textTheme.displayMedium),
                      const SizedBox(height: 4),
                      Text('Manage your connected devices',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => context.go('/devices/pair'),
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text('Pair Mobile via QR Code'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: const Key('add_device_button'),
                        onPressed: () => _showAddDeviceDialog(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Device'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Device List
              if (state is DeviceLoading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                )),

              if (state is DeviceLoaded) ...[
                if (state.devices.isEmpty)
                  _EmptyState()
                else
                  _DeviceGrid(devices: state.devices),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showAddDeviceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 480,
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
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.devices_rounded,
                          color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connect Physical Device',
                              style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 2),
                          Text('Zero-Assumption Cryptographic Onboarding',
                              style: TextStyle(
                                  color: AppTheme.textMutedColor(context),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PCOS requires real physical proof: database records cannot represent hardware without an authenticated PCOS agent or pairing handshake.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimaryColor(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Option 1: Phone or Tablet',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
                Text(
                  'Scan a one-time cryptographic QR code using the PCOS mobile app.',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      context.go('/devices/pair');
                    },
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Open QR Pairing Screen'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Option 2: PC, Mac, Server, or NAS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimaryColor(context))),
                const SizedBox(height: 6),
                Text(
                  'Run the official Rust agent on the machine terminal to discover disks and join your cloud:',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 13),
                ),
                const SizedBox(height: 10),
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
                              content: Text('Copied enrollment command to clipboard'),
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
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.devices_rounded,
                size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text('No devices registered',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor(context))),
          const SizedBox(height: 8),
          Text('Add your first device to start syncing files',
              style: TextStyle(
                  color: AppTheme.textMutedColor(context), fontSize: 14)),
        ],
      ),
    );
  }
}

class _DeviceGrid extends StatelessWidget {
  final List<Map<String, dynamic>> devices;
  const _DeviceGrid({required this.devices});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.6,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) => _DeviceCard(device: devices[index]),
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  const _DeviceCard({required this.device});

  IconData _getDeviceIcon(String type) {
    switch (type) {
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
      case 'raspberry_pi':
        return Icons.memory_rounded;
      default:
        return Icons.computer_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = device['is_online'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getDeviceIcon(device['device_type'] ?? ''),
                    size: 22, color: AppTheme.primary),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? AppTheme.success : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                          fontSize: 12,
                          color: isOnline
                              ? AppTheme.success
                              : AppTheme.textMuted)),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18, color: AppTheme.textMutedColor(context)),
                    tooltip: 'Device options',
                    padding: EdgeInsets.zero,
                    onSelected: (val) {
                      if (val == 'remove') {
                        _confirmRemoveDevice(context, device);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: AppTheme.error),
                            SizedBox(width: 8),
                            Text('Remove Device',
                                style: TextStyle(color: AppTheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device['name'] ?? '',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context)),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${device['os'] ?? ''} · ${device['device_type'] ?? ''}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textMutedColor(context))),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmRemoveDevice(BuildContext context, Map<String, dynamic> device) {
    final deviceId = device['id'] as String?;
    final deviceName = device['name'] as String? ?? 'Device';
    if (deviceId == null) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        title: const Text('Remove Device'),
        content: Text(
            'Are you sure you want to remove "$deviceName"? It will no longer sync with your personal cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<DeviceBloc>().add(DeviceRemoveRequested(deviceId));
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
