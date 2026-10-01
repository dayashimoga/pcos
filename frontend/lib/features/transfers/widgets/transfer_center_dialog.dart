import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/transfer_item.dart';
import '../services/transfer_manager.dart';

class TransferCenterDialog extends StatefulWidget {
  const TransferCenterDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const TransferCenterDialog(),
    );
  }

  @override
  State<TransferCenterDialog> createState() => _TransferCenterDialogState();
}

class _TransferCenterDialogState extends State<TransferCenterDialog> {
  final _transferManager = TransferManager();
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _transferManager.addListener(_onTransfersChanged);
  }

  @override
  void dispose() {
    _transferManager.removeListener(_onTransfersChanged);
    super.dispose();
  }

  void _onTransfersChanged() {
    if (mounted) setState(() {});
  }

  List<TransferItem> _filterItems(List<TransferItem> all) {
    switch (_selectedFilter) {
      case 'Uploads':
        return all.where((i) => i.type == TransferType.upload).toList();
      case 'Downloads':
        return all.where((i) => i.type == TransferType.download).toList();
      case 'Sync':
        return all.where((i) => i.type == TransferType.sync).toList();
      case 'Backup':
        return all.where((i) => i.type == TransferType.backup).toList();
      case 'Transcode':
        return all.where((i) => i.type == TransferType.transcode).toList();
      default:
        return all;
    }
  }

  IconData _iconForType(TransferType type) {
    switch (type) {
      case TransferType.upload:
        return Icons.upload_rounded;
      case TransferType.download:
        return Icons.download_rounded;
      case TransferType.sync:
        return Icons.sync_rounded;
      case TransferType.backup:
        return Icons.security_rounded;
      case TransferType.transcode:
        return Icons.video_settings_rounded;
    }
  }

  Color _colorForStatus(TransferStatus status) {
    switch (status) {
      case TransferStatus.inProgress:
        return AppTheme.primary;
      case TransferStatus.queued:
        return Colors.orangeAccent;
      case TransferStatus.paused:
        return Colors.amber;
      case TransferStatus.completed:
        return AppTheme.success;
      case TransferStatus.failed:
        return AppTheme.error;
      case TransferStatus.cancelled:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filterItems(_transferManager.items);
    final activeCount = _transferManager.activeCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppTheme.surfaceColor(context);
    final borderColor = AppTheme.borderColor(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 760,
        height: 580,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.swap_vert_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Transfer Center',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          if (activeCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$activeCount active',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        activeCount > 0
                            ? 'Speed: ${_transferManager.formattedAggregatedSpeed}'
                            : 'All transfers idle',
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Speed limiter dropdown
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _transferManager.bandwidthLimit,
                      hint: Text('Limit: None',
                          style: TextStyle(fontSize: 12, color: textMuted)),
                      dropdownColor: surfaceColor,
                      style: TextStyle(fontSize: 12, color: textPrimary),
                      icon:
                          Icon(Icons.speed_rounded, size: 16, color: textMuted),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Limit: Unlimited'),
                        ),
                        DropdownMenuItem(
                          value: 2 * 1024 * 1024,
                          child: Text('Limit: 2 MB/s'),
                        ),
                        DropdownMenuItem(
                          value: 5 * 1024 * 1024,
                          child: Text('Limit: 5 MB/s'),
                        ),
                        DropdownMenuItem(
                          value: 20 * 1024 * 1024,
                          child: Text('Limit: 20 MB/s'),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _transferManager.bandwidthLimit = val;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (activeCount > 0) ...[
                    IconButton(
                      icon: const Icon(Icons.pause_circle_outline_rounded),
                      tooltip: 'Pause All',
                      onPressed: () => _transferManager.pauseAll(),
                      color: textMuted,
                      iconSize: 20,
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      tooltip: 'Resume All',
                      onPressed: () => _transferManager.resumeAll(),
                      color: textMuted,
                      iconSize: 20,
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.clear_all_rounded),
                    tooltip: 'Clear Completed',
                    onPressed: () => _transferManager.clearCompleted(),
                    color: textMuted,
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    color: textMuted,
                    iconSize: 20,
                  ),
                ],
              ),
            ),

            // Filter Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  for (final tab in [
                    'All',
                    'Uploads',
                    'Downloads',
                    'Sync',
                    'Backup',
                    'Transcode'
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(tab),
                        selected: _selectedFilter == tab,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedFilter = tab);
                        },
                        selectedColor: AppTheme.primary.withOpacity(0.15),
                        checkmarkColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: _selectedFilter == tab
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _selectedFilter == tab
                              ? AppTheme.primary
                              : textMuted,
                        ),
                        backgroundColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: _selectedFilter == tab
                                ? AppTheme.primary.withOpacity(0.4)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_outlined,
                              size: 48, color: textMuted.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No active or queued transfers',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Files you upload, download, or sync will appear here.',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final item = items[idx];
                        final statusColor = _colorForStatus(item.status);

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFFFFFFF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(_iconForType(item.type),
                                        size: 18, color: statusColor),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              '${item.formattedTransferred} / ${item.formattedSize}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: textMuted,
                                              ),
                                            ),
                                            if (item
                                                .formattedSpeed.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text('•',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: textMuted)),
                                              const SizedBox(width: 8),
                                              Text(
                                                item.formattedSpeed,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: AppTheme.primary,
                                                ),
                                              ),
                                            ],
                                            if (item
                                                .formattedEta.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text('•',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: textMuted)),
                                              const SizedBox(width: 8),
                                              Text(
                                                item.formattedEta,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.status.name.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Control actions
                                  if (item.status ==
                                      TransferStatus.inProgress) ...[
                                    IconButton(
                                      icon: const Icon(Icons.pause_rounded),
                                      tooltip: 'Pause',
                                      iconSize: 18,
                                      color: textMuted,
                                      onPressed: () => _transferManager
                                          .pauseTransfer(item.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded),
                                      tooltip: 'Cancel',
                                      iconSize: 18,
                                      color: AppTheme.error,
                                      onPressed: () => _transferManager
                                          .cancelTransfer(item.id),
                                    ),
                                  ] else if (item.status ==
                                      TransferStatus.paused) ...[
                                    IconButton(
                                      icon:
                                          const Icon(Icons.play_arrow_rounded),
                                      tooltip: 'Resume',
                                      iconSize: 18,
                                      color: AppTheme.primary,
                                      onPressed: () => _transferManager
                                          .resumeTransfer(item.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded),
                                      tooltip: 'Cancel',
                                      iconSize: 18,
                                      color: AppTheme.error,
                                      onPressed: () => _transferManager
                                          .cancelTransfer(item.id),
                                    ),
                                  ] else if (item.status ==
                                      TransferStatus.failed) ...[
                                    IconButton(
                                      icon: const Icon(Icons.refresh_rounded),
                                      tooltip: 'Retry',
                                      iconSize: 18,
                                      color: AppTheme.primary,
                                      onPressed: () => _transferManager
                                          .retryTransfer(item.id),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Progress bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: item.progress,
                                  minHeight: 4,
                                  backgroundColor: borderColor,
                                  color: statusColor,
                                ),
                              ),
                              if (item.error != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.error!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
