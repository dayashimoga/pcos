import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class SendToDeviceSheet extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String? mimeType;
  final ApiClient apiClient;

  const SendToDeviceSheet({
    super.key,
    required this.fileId,
    required this.fileName,
    this.mimeType,
    required this.apiClient,
  });

  static Future<void> show(
    BuildContext context, {
    required String fileId,
    required String fileName,
    String? mimeType,
    required ApiClient apiClient,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SendToDeviceSheet(
        fileId: fileId,
        fileName: fileName,
        mimeType: mimeType,
        apiClient: apiClient,
      ),
    );
  }

  @override
  State<SendToDeviceSheet> createState() => _SendToDeviceSheetState();
}

class _SendToDeviceSheetState extends State<SendToDeviceSheet> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _devices = [];
  String? _selectedDeviceId;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.apiClient.dio.get('/api/v1/devices');
      if (mounted) {
        final list = res.data['devices'] as List<dynamic>? ?? [];
        setState(() {
          _devices = list;
          _isLoading = false;
          if (_devices.isNotEmpty) {
            _selectedDeviceId = _devices.first['id']?.toString();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load devices: ${e.toString().replaceAll("Exception: ", "")}';
          _isLoading = false;
        });
      }
    }
  }

  bool get _isVideo {
    final mime = widget.mimeType;
    if (mime != null && mime.startsWith('video/')) return true;
    final name = widget.fileName.toLowerCase();
    return name.endsWith('.mp4') || name.endsWith('.mkv') || name.endsWith('.mov') || name.endsWith('.webm');
  }

  Future<void> _dispatchCommand(String command) async {
    if (_selectedDeviceId == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      await widget.apiClient.sendCommand(
        targetDeviceId: _selectedDeviceId!,
        command: command,
        payload: {
          'file_id': widget.fileId,
          'file_name': widget.fileName,
          'mime_type': widget.mimeType,
          'sent_at': DateTime.now().toIso8601String(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              command == 'play_on_tv'
                  ? 'Playing "${widget.fileName}" on TV...'
                  : 'Command sent to device successfully',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  IconData _getDeviceIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'tv':
        return Icons.tv;
      case 'desktop':
      case 'laptop':
        return Icons.computer;
      case 'phone':
        return Icons.smartphone;
      case 'tablet':
        return Icons.tablet;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.cast_connected_outlined, color: colorScheme.secondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send to Device',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: TextStyle(color: colorScheme.error)),
            )
          else if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No paired devices found. Pair a PC, Laptop, or TV to use remote actions.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Text(
              'Select Destination Device:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),

            ..._devices.map((dev) {
              final id = dev['id']?.toString() ?? '';
              final name = dev['name']?.toString() ?? 'Unnamed Device';
              final type = dev['device_type']?.toString() ?? 'device';
              final isOnline = dev['is_online'] == true || dev['is_online'] == 1;
              final isSelected = _selectedDeviceId == id;

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedDeviceId = id;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer.withOpacity(0.25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withOpacity(0.4),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getDeviceIcon(type),
                        color: isOnline ? colorScheme.primary : colorScheme.outline,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            Text(
                              isOnline ? 'Online' : 'Offline',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isOnline ? Colors.green.shade600 : colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Radio<String>(
                        value: id,
                        groupValue: _selectedDeviceId,
                        onChanged: (val) {
                          setState(() {
                            _selectedDeviceId = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 18),

            // Contextual Actions
            Row(
              children: [
                if (_isVideo) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSending ? null : () => _dispatchCommand('play_on_tv'),
                      icon: const Icon(Icons.tv, size: 18),
                      label: const Text('Play on TV'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSending ? null : () => _dispatchCommand('send_to_device'),
                    icon: const Icon(Icons.send_to_mobile, size: 18),
                    label: const Text('Send to Device'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
