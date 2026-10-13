import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/transfer_item.dart';
import '../services/transfer_manager.dart';

/// Full-page Transfers hub with real-time progress, speed, filtering, and controls.
class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
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
      case 'Active':
        return all.where((i) => i.status == TransferStatus.inProgress || i.status == TransferStatus.queued).toList();
      case 'Uploads':
        return all.where((i) => i.type == TransferType.upload).toList();
      case 'Downloads':
        return all.where((i) => i.type == TransferType.download).toList();
      case 'Sync':
        return all.where((i) => i.type == TransferType.sync).toList();
      case 'Backup':
        return all.where((i) => i.type == TransferType.backup).toList();
      case 'Completed':
        return all.where((i) => i.status == TransferStatus.completed).toList();
      case 'Failed':
        return all.where((i) => i.status == TransferStatus.failed).toList();
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

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _transferManager.items;
    final items = _filterItems(allItems);
    final activeCount = _transferManager.activeCount;
    final completedCount = allItems.where((i) => i.status == TransferStatus.completed).length;
    final failedCount = allItems.where((i) => i.status == TransferStatus.failed).length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppTheme.surfaceColor(context);
    final borderColor = AppTheme.borderColor(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);

    // Compute total active speed
    final totalSpeed = allItems
        .where((i) => i.status == TransferStatus.inProgress)
        .fold<double>(0.0, (acc, item) => acc + item.speedBps);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Transfers', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (completedCount > 0)
            TextButton.icon(
              onPressed: () => _transferManager.clearCompleted(),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Clear Completed'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          final cardWidth = constraints.maxWidth < 360
              ? (constraints.maxWidth - 44) / 2
              : (isCompact ? 140.0 : 180.0);

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 24,
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview Stat Cards
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatCard('Active', activeCount.toString(), Icons.swap_vert_rounded, AppTheme.primary, cardWidth, surfaceColor, borderColor, textPrimary, textMuted),
                    _buildStatCard('Speed', _formatSpeed(totalSpeed), Icons.speed_rounded, Colors.purpleAccent, cardWidth, surfaceColor, borderColor, textPrimary, textMuted),
                    _buildStatCard('Completed', completedCount.toString(), Icons.check_circle_rounded, AppTheme.success, cardWidth, surfaceColor, borderColor, textPrimary, textMuted),
                    if (failedCount > 0)
                      _buildStatCard('Failed', failedCount.toString(), Icons.error_outline_rounded, AppTheme.error, cardWidth, surfaceColor, borderColor, textPrimary, textMuted),
                  ],
                ),
                const SizedBox(height: 16),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'All',
                      'Active',
                      'Uploads',
                      'Downloads',
                      'Sync',
                      'Backup',
                      'Completed',
                      if (failedCount > 0) 'Failed',
                    ].map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(filter),
                          onSelected: (_) => setState(() => _selectedFilter = filter),
                          backgroundColor: surfaceColor,
                          selectedColor: AppTheme.primary.withOpacity(0.2),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected ? AppTheme.primary : textMuted,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primary : borderColor,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Transfer Items List
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_done_rounded, size: 64, color: textMuted.withOpacity(0.4)),
                              const SizedBox(height: 16),
                              Text(
                                _selectedFilter == 'All'
                                    ? 'No active transfers'
                                    : 'No ${_selectedFilter.toLowerCase()} transfers',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Uploads, downloads, and sync operations will appear here in real-time.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: textMuted),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final progress = item.progress;
                            final color = _colorForStatus(item.status);

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(_iconForType(item.type), color: color, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 2,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  '${_formatBytes(item.transferredBytes)} / ${_formatBytes(item.sizeBytes)}',
                                                  style: TextStyle(fontSize: 11, color: textMuted),
                                                ),
                                                if (item.status == TransferStatus.inProgress && item.speedBps > 0) ...[
                                                  Text('•', style: TextStyle(color: textMuted)),
                                                  Text(
                                                    _formatSpeed(item.speedBps),
                                                    style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: color.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    item.status.name.toUpperCase(),
                                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // Action buttons with compact constraints
                                      if (item.status == TransferStatus.inProgress)
                                        IconButton(
                                          icon: const Icon(Icons.pause_rounded, size: 18),
                                          tooltip: 'Pause',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          padding: EdgeInsets.zero,
                                          onPressed: () => _transferManager.pauseTransfer(item.id),
                                        )
                                      else if (item.status == TransferStatus.paused)
                                        IconButton(
                                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                          tooltip: 'Resume',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          padding: EdgeInsets.zero,
                                          onPressed: () => _transferManager.resumeTransfer(item.id),
                                        )
                                      else if (item.status == TransferStatus.failed)
                                        IconButton(
                                          icon: const Icon(Icons.refresh_rounded, size: 18),
                                          tooltip: 'Retry',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          padding: EdgeInsets.zero,
                                          onPressed: () => _transferManager.retryTransfer(item.id),
                                        ),
                                      if (item.status == TransferStatus.inProgress || item.status == TransferStatus.queued || item.status == TransferStatus.paused)
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                          tooltip: 'Cancel',
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          padding: EdgeInsets.zero,
                                          onPressed: () => _transferManager.cancelTransfer(item.id),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                      valueColor: AlwaysStoppedAnimation<Color>(color),
                                      minHeight: 4,
                                    ),
                                  ),
                                  if (item.error != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      item.error!,
                                      style: const TextStyle(fontSize: 11, color: AppTheme.error),
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
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    double cardWidth,
    Color surfaceColor,
    Color borderColor,
    Color textPrimary,
    Color textMuted,
  ) {
    return Container(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: textMuted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
