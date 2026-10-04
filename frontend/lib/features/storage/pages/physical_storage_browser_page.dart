import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;
import '../../files/repository/file_repository.dart';

// Web download helper
import 'physical_browser_web.dart'
    if (dart.library.io) 'physical_browser_stub.dart' as platform;

/// Physical Storage Node Filesystem Browser
/// Directly browses real agent disks over authenticated TLS/WSS tunnels.
class PhysicalStorageBrowserPage extends StatefulWidget {
  final String nodeId;
  final String nodeName;
  final String storagePath;
  final bool isOnline;

  const PhysicalStorageBrowserPage({
    super.key,
    required this.nodeId,
    required this.nodeName,
    required this.storagePath,
    required this.isOnline,
  });

  @override
  State<PhysicalStorageBrowserPage> createState() =>
      _PhysicalStorageBrowserPageState();
}

class _PhysicalStorageBrowserPageState
    extends State<PhysicalStorageBrowserPage> {
  late final FileRepository _repo;

  String _currentPath = '';
  List<String> _breadcrumbs = [];
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  bool _isGridView = false;
  String _sortBy = 'name'; // 'name', 'size', 'date'
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _repo = getIt<FileRepository>();
    _loadDirectory('');
  }

  void _updateBreadcrumbs(String path) {
    if (path.isEmpty) {
      _breadcrumbs = [];
    } else {
      final parts =
          path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
      _breadcrumbs = parts;
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _repo.listStorageNodeFs(widget.nodeId, path: path);
      final rawEntries = res['entries'] as List? ?? [];
      final entries =
          rawEntries.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (mounted) {
        setState(() {
          _currentPath = path;
          _updateBreadcrumbs(path);
          _entries = entries;
          _loading = false;
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

  void _navigateToFolder(String folderName) {
    final newPath =
        _currentPath.isEmpty ? folderName : '$_currentPath/$folderName';
    _loadDirectory(newPath);
  }

  void _navigateToBreadcrumb(int index) {
    if (index < 0) {
      _loadDirectory('');
    } else {
      final targetPath = _breadcrumbs.sublist(0, index + 1).join('/');
      _loadDirectory(targetPath);
    }
  }

  List<Map<String, dynamic>> get _filteredAndSortedEntries {
    var list = _entries.where((e) {
      final name = (e['name'] ?? '').toString().toLowerCase();
      if (_searchQuery.isNotEmpty &&
          !name.contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      final isDirA = a['is_dir'] == true;
      final isDirB = b['is_dir'] == true;

      // Folders always first
      if (isDirA && !isDirB) return -1;
      if (!isDirA && isDirB) return 1;

      int comp = 0;
      if (_sortBy == 'size') {
        final sA = (a['size_bytes'] as num?)?.toInt() ?? 0;
        final sB = (b['size_bytes'] as num?)?.toInt() ?? 0;
        comp = sA.compareTo(sB);
      } else if (_sortBy == 'date') {
        final dA = (a['modified'] as num?)?.toInt() ?? 0;
        final dB = (b['modified'] as num?)?.toInt() ?? 0;
        comp = dA.compareTo(dB);
      } else {
        final nA = (a['name'] ?? '').toString().toLowerCase();
        final nB = (b['name'] ?? '').toString().toLowerCase();
        comp = nA.compareTo(nB);
      }

      return _sortAsc ? comp : -comp;
    });

    return list;
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
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
            child: const Icon(Icons.create_new_folder_rounded,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('New Remote Folder',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final targetPath =
                  _currentPath.isEmpty ? name : '$_currentPath/$name';
              try {
                await _repo.mkdirStorageNodeFs(widget.nodeId, targetPath);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Folder "$name" created'),
                  backgroundColor: AppTheme.success,
                ));
                _loadDirectory(_currentPath);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ApiClient.formatError(e)),
                  backgroundColor: AppTheme.error,
                ));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(Map<String, dynamic> entry) {
    final name = entry['name'] ?? 'item';
    final isDir = entry['is_dir'] == true;
    final itemPath = _currentPath.isEmpty ? name : '$_currentPath/$name';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_forever_rounded,
                color: AppTheme.error, size: 20),
          ),
          const SizedBox(width: 12),
          Text(isDir ? 'Delete Folder?' : 'Delete File?',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          'Are you sure you want to permanently delete "$name" from physical storage?\nThis action cannot be undone.',
          style:
              TextStyle(fontSize: 13, color: AppTheme.textMutedColor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _repo.deleteStorageNodeFs(
                  widget.nodeId,
                  itemPath,
                  recursive: isDir,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('"$name" deleted'),
                  backgroundColor: AppTheme.success,
                ));
                _loadDirectory(_currentPath);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ApiClient.formatError(e)),
                  backgroundColor: AppTheme.error,
                ));
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _previewOrStreamFile(Map<String, dynamic> entry) {
    final name = entry['name']?.toString() ?? 'File';
    final itemPath = _currentPath.isEmpty ? name : '$_currentPath/$name';
    final streamUrl = _repo.nodeFsStreamUrl(widget.nodeId, itemPath);

    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage =
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
    final isVideo = ['mp4', 'mkv', 'webm', 'mov', 'avi'].contains(ext);
    final isAudio = ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'].contains(ext);
    final isText = [
      'txt',
      'md',
      'json',
      'yaml',
      'yml',
      'xml',
      'csv',
      'rs',
      'dart',
      'ts',
      'js',
      'py',
      'sh',
      'log',
      'toml',
      'env'
    ].contains(ext);

    if (isImage) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(name,
                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: Colors.white70),
                    onPressed: () => platform.downloadFileUrl(streamUrl, name),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    streamUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('Failed to load image',
                          style: TextStyle(color: Colors.white60)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (isVideo || isAudio) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded,
                color: AppTheme.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.accent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PCOS Data Plane: Live HTTP 206 Partial Content range stream directly from physical disk.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _repo.probeStorageNodeMedia(widget.nodeId, itemPath),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Probing media with host FFmpeg engine...',
                            style: TextStyle(fontSize: 12)),
                      ]),
                    );
                  }
                  if (snap.hasData &&
                      snap.data != null &&
                      snap.data!['format_name'] != null) {
                    final data = snap.data!;
                    final durationSecs =
                        (data['duration_secs'] as num?)?.toDouble() ?? 0.0;
                    final mins = (durationSecs / 60).floor();
                    final secs = (durationSecs % 60).floor();
                    final timeFormatted = '${mins}m ${secs}s';
                    final vCodec =
                        data['video_codec']?.toString().toUpperCase() ?? 'N/A';
                    final aCodec =
                        data['audio_codec']?.toString().toUpperCase() ?? 'N/A';
                    final w = data['width'];
                    final h = data['height'];
                    final resStr = (w != null && h != null) ? '${w}x$h' : null;

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppTheme.borderColor(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.analytics_rounded,
                                size: 14, color: AppTheme.primary),
                            SizedBox(width: 6),
                            Text('Physical FFmpeg Probe Analysis',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (resStr != null)
                                _MetadataTag(
                                    label: 'Resolution', value: resStr),
                              _MetadataTag(label: 'Video', value: vCodec),
                              _MetadataTag(label: 'Audio', value: aCodec),
                              if (durationSecs > 0)
                                _MetadataTag(
                                    label: 'Duration', value: timeFormatted),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Stream URL:\n$streamUrl',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: streamUrl));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Stream URL copied to clipboard'),
                  duration: Duration(seconds: 2),
                ));
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Stream URL'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                platform.downloadFileUrl(streamUrl, name);
              },
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Download Media'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    if (isText) {
      _showTextFilePreview(name, itemPath, streamUrl);
      return;
    }

    // Default download trigger
    platform.downloadFileUrl(streamUrl, name);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Downloading "$name" via data plane relay...'),
      backgroundColor: AppTheme.primary,
    ));
  }

  void _showTextFilePreview(
      String name, String itemPath, String streamUrl) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: _repo.readStorageNodeFsChunk(widget.nodeId, itemPath,
            offset: 0, length: 65536),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          String textContent = '';
          if (snapshot.hasData && snapshot.data!['data_base64'] != null) {
            try {
              final bytes = base64Decode(snapshot.data!['data_base64']);
              textContent = utf8.decode(bytes, allowMalformed: true);
            } catch (e) {
              textContent = 'Error decoding text file: $e';
            }
          } else {
            textContent =
                'Unable to read file content: ${snapshot.error ?? "Empty chunk"}';
          }

          return Dialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 800,
              height: 600,
              child: Column(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Row(children: [
                      const Icon(Icons.description_rounded, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'Copy Content',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: textContent));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text('Content copied to clipboard'),
                          ));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_rounded, size: 18),
                        tooltip: 'Download',
                        onPressed: () =>
                            platform.downloadFileUrl(streamUrl, name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.black.withOpacity(0.1),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          textContent,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _triggerUpload() {
    platform.pickAndUploadToNode(
      context: context,
      nodeId: widget.nodeId,
      currentPath: _currentPath,
      onComplete: () {
        _loadDirectory(_currentPath);
      },
    );
  }

  IconData _getFileIcon(String name, bool isDir) {
    if (isDir) return Icons.folder_rounded;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
        return Icons.image_rounded;
      case 'mp4':
      case 'mkv':
      case 'webm':
      case 'mov':
      case 'avi':
        return Icons.movie_rounded;
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return Icons.audiotrack_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.archive_rounded;
      case 'rs':
      case 'dart':
      case 'ts':
      case 'js':
      case 'py':
      case 'html':
      case 'css':
      case 'json':
        return Icons.code_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileColor(String name, bool isDir) {
    if (isDir) return AppTheme.primary;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return AppTheme.accent;
      case 'mp4':
      case 'mkv':
      case 'webm':
        return Colors.deepPurpleAccent;
      case 'mp3':
      case 'flac':
      case 'wav':
        return Colors.teal;
      case 'pdf':
        return AppTheme.error;
      case 'zip':
      case 'tar':
      case 'gz':
        return Colors.amber.shade700;
      case 'rs':
      case 'dart':
      case 'ts':
      case 'js':
      case 'py':
        return Colors.lightBlueAccent;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredAndSortedEntries;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(widget.nodeName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      (widget.isOnline ? AppTheme.success : AppTheme.textMuted)
                          .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        widget.isOnline ? AppTheme.success : AppTheme.textMuted,
                  ),
                ),
              ),
            ]),
            Text(
              'Physical Mount: ${widget.storagePath}',
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textMutedColor(context)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _loadDirectory(_currentPath),
          ),
          IconButton(
            icon: Icon(_isGridView
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumbs Bar & Action Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor(context)),
              ),
            ),
            child: Row(
              children: [
                // Root Breadcrumb
                InkWell(
                  onTap: () => _navigateToBreadcrumb(-1),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.storage_rounded,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(widget.storagePath,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
                // Segments
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_breadcrumbs.length, (idx) {
                        final seg = _breadcrumbs[idx];
                        return Row(
                          children: [
                            const Icon(Icons.chevron_right_rounded,
                                size: 16, color: Colors.grey),
                            InkWell(
                              onTap: () => _navigateToBreadcrumb(idx),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                child: Text(
                                  seg,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: idx == _breadcrumbs.length - 1
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: idx == _breadcrumbs.length - 1
                                        ? AppTheme.primary
                                        : AppTheme.textPrimaryColor(context),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                // Quick Action Buttons
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _showCreateFolderDialog,
                  icon: const Icon(Icons.create_new_folder_rounded, size: 16),
                  label:
                      const Text('New Folder', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _triggerUpload,
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label:
                      const Text('Upload File', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppTheme.surfaceColor(context),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search files and folders...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: AppTheme.borderColor(context)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                        value: 'name', child: Text('Sort by Name')),
                    DropdownMenuItem(
                        value: 'size', child: Text('Sort by Size')),
                    DropdownMenuItem(
                        value: 'date', child: Text('Sort by Date')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sortBy = val);
                  },
                ),
                IconButton(
                  icon: Icon(
                      _sortAsc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 18),
                  tooltip: _sortAsc ? 'Ascending' : 'Descending',
                  onPressed: () => setState(() => _sortAsc = !_sortAsc),
                ),
              ],
            ),
          ),

          // Main Content View
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded,
                                  size: 48, color: AppTheme.error),
                              const SizedBox(height: 16),
                              Text('Physical Storage Error',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppTheme.textMutedColor(context)),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () => _loadDirectory(_currentPath),
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Retry Connection'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_open_rounded,
                                    size: 56,
                                    color: Colors.grey.withOpacity(0.5)),
                                const SizedBox(height: 16),
                                const Text('This directory is empty',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload a file or create a folder on this physical drive.',
                                  style: TextStyle(
                                      color: AppTheme.textMutedColor(context),
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : _isGridView
                            ? _buildGridView(items)
                            : _buildListView(items),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: AppTheme.borderColor(context).withOpacity(0.5),
      ),
      itemBuilder: (context, idx) {
        final item = items[idx];
        final isDir = item['is_dir'] == true;
        final name = item['name']?.toString() ?? 'unknown';
        final sizeBytes = (item['size_bytes'] as num?)?.toInt() ?? 0;
        final color = _getFileColor(name, isDir);
        final icon = _getFileIcon(name, isDir);

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(name,
              style: TextStyle(
                fontWeight: isDir ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              )),
          subtitle: Text(
            isDir ? 'Directory' : formatFileSize(sizeBytes),
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMutedColor(context),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDir)
                IconButton(
                  icon: const Icon(Icons.play_circle_fill_rounded,
                      color: AppTheme.accent, size: 22),
                  tooltip: 'Stream / Preview',
                  onPressed: () => _previewOrStreamFile(item),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error, size: 20),
                tooltip: 'Delete',
                onPressed: () => _showDeleteConfirm(item),
              ),
            ],
          ),
          onTap: () {
            if (isDir) {
              _navigateToFolder(name);
            } else {
              _previewOrStreamFile(item);
            }
          },
        );
      },
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        final isDir = item['is_dir'] == true;
        final name = item['name']?.toString() ?? 'unknown';
        final sizeBytes = (item['size_bytes'] as num?)?.toInt() ?? 0;
        final color = _getFileColor(name, isDir);
        final icon = _getFileIcon(name, isDir);

        return InkWell(
          onTap: () {
            if (isDir) {
              _navigateToFolder(name);
            } else {
              _previewOrStreamFile(item);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: isDir ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDir ? 'Folder' : formatFileSize(sizeBytes),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMutedColor(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetadataTag extends StatelessWidget {
  final String label;
  final String value;
  const _MetadataTag({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label: $value',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}
