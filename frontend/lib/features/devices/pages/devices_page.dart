import 'package:flutter/material.dart';
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
                      OutlinedButton.icon(
                        onPressed: () => context.go('/devices/pair'),
                        icon: const Icon(Icons.qr_code_rounded, size: 18),
                        label: const Text('Pair Mobile via QR Code'),
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
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedType = 'desktop';
    String selectedOs = 'Windows';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Register Device',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      const Text('Add a new device to your cloud',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13)),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('device_name_field'),
                        controller: nameController,
                        decoration: const InputDecoration(
                            labelText: 'Device Name',
                            hintText: 'e.g. My Laptop'),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration:
                            const InputDecoration(labelText: 'Device Type'),
                        dropdownColor: AppTheme.surfaceLight,
                        items: const [
                          DropdownMenuItem(
                              value: 'desktop', child: Text('Desktop')),
                          DropdownMenuItem(
                              value: 'laptop', child: Text('Laptop')),
                          DropdownMenuItem(
                              value: 'phone', child: Text('Phone')),
                          DropdownMenuItem(
                              value: 'tablet', child: Text('Tablet')),
                          DropdownMenuItem(
                              value: 'server', child: Text('Server')),
                          DropdownMenuItem(value: 'nas', child: Text('NAS')),
                          DropdownMenuItem(
                              value: 'raspberry_pi',
                              child: Text('Raspberry Pi')),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedType = v!),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedOs,
                        decoration: const InputDecoration(
                            labelText: 'Operating System'),
                        dropdownColor: AppTheme.surfaceLight,
                        items: const [
                          DropdownMenuItem(
                              value: 'Windows', child: Text('Windows')),
                          DropdownMenuItem(
                              value: 'macOS', child: Text('macOS')),
                          DropdownMenuItem(
                              value: 'Linux', child: Text('Linux')),
                          DropdownMenuItem(
                              value: 'Android', child: Text('Android')),
                          DropdownMenuItem(value: 'iOS', child: Text('iOS')),
                        ],
                        onChanged: (v) => setDialogState(() => selectedOs = v!),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel')),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            key: const Key('device_register_submit'),
                            onPressed: () {
                              if (formKey.currentState?.validate() ?? false) {
                                context
                                    .read<DeviceBloc>()
                                    .add(DeviceRegisterRequested(
                                      name: nameController.text.trim(),
                                      deviceType: selectedType,
                                      os: selectedOs,
                                      osVersion: '',
                                    ));
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('Register'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
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
          const Text('No devices registered',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Add your first device to start syncing files',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
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
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device['name'] ?? '',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${device['os'] ?? ''} · ${device['device_type'] ?? ''}',
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}
