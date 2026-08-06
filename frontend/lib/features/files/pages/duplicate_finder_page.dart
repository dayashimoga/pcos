import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// Finds duplicate files by comparing file sizes and names across the user's storage.
class DuplicateFinderPage extends StatefulWidget {
  const DuplicateFinderPage({super.key});

  @override
  State<DuplicateFinderPage> createState() => _DuplicateFinderPageState();
}

class _DuplicateFinderPageState extends State<DuplicateFinderPage> {
  bool _scanning = false;
  bool _scanned = false;
  List<List<Map<String, dynamic>>> _duplicateGroups = [];
  int _totalFilesScanned = 0;
  int _totalDuplicates = 0;
  int _spaceSavable = 0;

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _scanned = false;
      _duplicateGroups = [];
    });

    try {
      final api = getIt<ApiClient>();
      // Fetch all files via search wildcard
      final resp =
          await api.dio.get('/api/v1/search', queryParameters: {'q': '*'});
      final results = List<Map<String, dynamic>>.from(
          resp.data['results'] ?? resp.data['entries'] ?? []);

      // Filter to files only
      final files = results.where((f) => f['entry_type'] == 'file').toList();
      _totalFilesScanned = files.length;

      // Group by (name, size_bytes) to find duplicates
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final file in files) {
        final key =
            '${(file['name'] ?? '').toString().toLowerCase()}|${file['size_bytes'] ?? 0}';
        groups.putIfAbsent(key, () => []).add(file);
      }

      // Keep only groups with 2+ files
      _duplicateGroups = groups.values.where((g) => g.length > 1).toList();
      _totalDuplicates =
          _duplicateGroups.fold(0, (sum, g) => sum + g.length - 1);
      _spaceSavable = _duplicateGroups.fold(
          0,
          (sum, g) =>
              sum + ((g.first['size_bytes'] ?? 0) as int) * (g.length - 1));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Scan failed: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }

    if (mounted) {
      setState(() {
        _scanning = false;
        _scanned = true;
      });
    }
  }

  void _deleteFile(String fileId, int groupIndex) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.delete('/api/v1/files/$fileId');
      setState(() {
        _duplicateGroups[groupIndex].removeWhere((f) => f['id'] == fileId);
        if (_duplicateGroups[groupIndex].length < 2) {
          _duplicateGroups.removeAt(groupIndex);
        }
        _totalDuplicates =
            _duplicateGroups.fold(0, (sum, g) => sum + g.length - 1);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('File moved to trash'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  String _formatSize(dynamic bytes) {
    final b = (bytes is int) ? bytes.toDouble() : 0.0;
    if (b < 1024) return '${b.toInt()} B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 24 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Text('Duplicate Finder',
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        Text('Find and remove duplicate files to free up space',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // Scan button + stats
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor(context))),
          child: Column(children: [
            if (!_scanned && !_scanning) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppTheme.primary.withOpacity(0.15),
                      AppTheme.accent.withOpacity(0.1)
                    ]),
                    borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.find_replace_rounded,
                    size: 48, color: AppTheme.primary),
              ),
              const SizedBox(height: 20),
              Text('Scan for Duplicates',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 8),
              Text(
                  'Compares file names and sizes to identify potential duplicates',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _runScan,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Start Scan'),
              ),
            ],
            if (_scanning) ...[
              const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 20),
              Text('Scanning files...',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 8),
              Text('Comparing file sizes and names',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 14)),
            ],
            if (_scanned) ...[
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _StatCard(
                    label: 'Files Scanned',
                    value: '$_totalFilesScanned',
                    icon: Icons.description_rounded,
                    color: AppTheme.primary),
                _StatCard(
                    label: 'Duplicates',
                    value: '$_totalDuplicates',
                    icon: Icons.copy_all_rounded,
                    color: _totalDuplicates > 0
                        ? AppTheme.error
                        : AppTheme.success),
                _StatCard(
                    label: 'Savable Space',
                    value: _formatSize(_spaceSavable),
                    icon: Icons.storage_rounded,
                    color: AppTheme.accent),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _runScan,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Re-scan'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 24),

        // Results
        if (_scanned && _duplicateGroups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context))),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.check_circle_rounded,
                    size: 40, color: AppTheme.success),
              ),
              const SizedBox(height: 16),
              Text('No duplicates found!',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 4),
              Text('Your files are organized without duplicates',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 14)),
            ]),
          ),

        if (_scanned && _duplicateGroups.isNotEmpty)
          ...List.generate(_duplicateGroups.length, (gi) {
            final group = _duplicateGroups[gi];
            final name = group.first['name'] ?? 'Unknown';
            final size = _formatSize(group.first['size_bytes'] ?? 0);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor(context))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: AppTheme.borderColor(context)))),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: AppTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.copy_all_rounded,
                              size: 18, color: AppTheme.error),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimaryColor(context)),
                                  overflow: TextOverflow.ellipsis),
                              Text('${group.length} copies · $size each',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.textMutedColor(context))),
                            ])),
                      ]),
                    ),
                    // File rows
                    ...List.generate(group.length, (fi) {
                      final file = group[fi];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(children: [
                          if (fi == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: AppTheme.success.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6)),
                              child: const Text('Keep',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.success)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: AppTheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6)),
                              child: const Text('Dup',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.error)),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                'ID: ${(file['id'] ?? '').toString().substring(0, 8)}...',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMutedColor(context),
                                    fontFamily: 'monospace')),
                          ),
                          if (fi > 0)
                            TextButton.icon(
                              onPressed: () => _deleteFile(file['id'], gi),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 16, color: AppTheme.error),
                              label: const Text('Remove',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.error)),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8)),
                            ),
                        ]),
                      );
                    }),
                    const SizedBox(height: 4),
                  ]),
            );
          }),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: AppTheme.textMutedColor(context))),
      ]);
}
