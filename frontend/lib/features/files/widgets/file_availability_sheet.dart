import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

enum AvailabilityTier {
  thisDeviceOnly('local_only', 'This device only',
      'Stored exclusively on this node. Unavailable when device is offline.'),
  anyOfMyDevices('any_device', 'Any of my devices',
      'Synced on-demand across your paired devices when both are online.'),
  alwaysAvailable('always_available', 'Always available remotely',
      'Replicated to encrypted Cloudflare R2 cache or always-on storage node.'),
  keepRedundantCopy('redundant', 'Keep redundant copy',
      'Mirrored to at least two independent user-owned storage nodes.'),
  archive('archive', 'Archive',
      'Cold compressed storage on primary node with off-site recovery bundle.');

  final String id;
  final String label;
  final String description;

  const AvailabilityTier(this.id, this.label, this.description);
}

class FileAvailabilitySheet extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String initialTier;
  final ApiClient apiClient;

  const FileAvailabilitySheet({
    super.key,
    required this.fileId,
    required this.fileName,
    this.initialTier = 'local_only',
    required this.apiClient,
  });

  static Future<void> show(
    BuildContext context, {
    required String fileId,
    required String fileName,
    String initialTier = 'local_only',
    required ApiClient apiClient,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FileAvailabilitySheet(
        fileId: fileId,
        fileName: fileName,
        initialTier: initialTier,
        apiClient: apiClient,
      ),
    );
  }

  @override
  State<FileAvailabilitySheet> createState() => _FileAvailabilitySheetState();
}

class _FileAvailabilitySheetState extends State<FileAvailabilitySheet> {
  late String _selectedTier;
  bool _isSaving = false;
  bool _isReplicating = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.initialTier;
  }

  Future<void> _saveAvailability() async {
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      await widget.apiClient.setFileAvailability(widget.fileId, _selectedTier);

      if (_selectedTier == AvailabilityTier.alwaysAvailable.id) {
        setState(() {
          _isReplicating = true;
        });
        await widget.apiClient.replicateFile(widget.fileId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedTier == AvailabilityTier.alwaysAvailable.id
                  ? 'Availability updated: Encrypted replication initiated'
                  : 'Availability updated successfully',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context, _selectedTier);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage =
              'Error: ${e.toString().replaceAll("Exception: ", "")}';
          _isSaving = false;
          _isReplicating = false;
        });
      }
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
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
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Availability Policy',
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

          // Cloud Budget Notice Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.tertiaryContainer,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: colorScheme.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Free-Tier Guard: Cloud storage is quota and budget-aware. Normal files transfer directly device-to-device without cloud proxying.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Availability Tier Radios
          ...AvailabilityTier.values.map((tier) {
            final isSelected = _selectedTier == tier.id;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedTier = tier.id;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer.withOpacity(0.3)
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<String>(
                      value: tier.id,
                      groupValue: _selectedTier,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTier = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tier.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],

          const SizedBox(height: 18),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveAvailability,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(_isReplicating
                                ? 'Replicating...'
                                : 'Saving...'),
                          ],
                        )
                      : const Text('Apply Policy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
