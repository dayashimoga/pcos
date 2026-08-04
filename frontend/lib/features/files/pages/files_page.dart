import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // ignore: unused_import
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/file_bloc.dart';

// Conditional import for web file picker
import 'files_page_stub.dart'
    if (dart.library.html) 'files_page_web.dart' as platform;

class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FileBloc>()..add(const FilesLoadRequested()),
      child: const _FilesContent(),
    );
  }
}

class _FilesContent extends StatefulWidget {
  const _FilesContent();

  @override
  State<_FilesContent> createState() => _FilesContentState();
}

class _FilesContentState extends State<_FilesContent> {
  bool _isGridView = true;
  String? _currentFolderId;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return BlocConsumer<FileBloc, FileState>(
      listener: (context, state) {
        if (state is FileActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(state.message),
            ]),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
          context.read<FileBloc>().add(FilesLoadRequested(folderId: _currentFolderId));
        } else if (state is FileError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.error_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(state.message)),
            ]),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      },
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () async {
            context.read<FileBloc>().add(FilesLoadRequested(folderId: _currentFolderId));
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, isWide ? 24 : 16, isWide ? 24 : 16, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Title row — responsive
                    if (isWide)
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Files', style: Theme.of(context).textTheme.displayMedium),
                          const SizedBox(height: 4),
                          Text('Manage your files and folders', style: Theme.of(context).textTheme.bodyLarge),
                        ])),
                        _buildToolbar(context),
                      ])
                    else ...[
                      Text('Files', style: Theme.of(context).textTheme.headlineLarge),
                      const SizedBox(height: 12),
                      _buildToolbar(context),
                    ],
                    const SizedBox(height: 16),

                    // Breadcrumb
                    if (state is FileLoaded && state.breadcrumb.isNotEmpty)
                      _Breadcrumb(items: state.breadcrumb, onTap: (id) {
                        _currentFolderId = id;
                        context.read<FileBloc>().add(FilesLoadRequested(folderId: id));
                      }),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),

              // Content
              if (state is FileLoading)
                SliverToBoxAdapter(child: _buildLoadingSkeleton(isWide))
              else if (state is FileError)
                SliverToBoxAdapter(child: _buildErrorState(context, state.message))
              else if (state is FileLoaded && state.entries.isEmpty)
                SliverToBoxAdapter(child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                  child: _EmptyFolder(onUpload: () => _handleUpload(context), onNewFolder: () => _showNewFolderDialog(context)),
                ))
              else if (state is FileLoaded) ...[
                if (_isGridView)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                    sliver: SliverLayoutBuilder(builder: (context, constraints) {
                      final w = constraints.crossAxisExtent;
                      final cols = w >= 1200 ? 6 : w >= 900 ? 5 : w >= 600 ? 3 : 2;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.0,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _FileGridCard(entry: state.entries[i], onTap: () => _handleItemTap(context, state.entries[i]), onAction: (a) => _handleAction(context, state.entries[i], a)),
                          childCount: state.entries.length,
                        ),
                      );
                    }),
                  )
                else
                  SliverToBoxAdapter(child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                    child: _FileList(entries: state.entries, onTap: (e) => _handleItemTap(context, e), onAction: (e, a) => _handleAction(context, e, a)),
                  )),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      // View toggle
      Container(
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ViewToggle(icon: Icons.grid_view_rounded, active: _isGridView, onTap: () => setState(() => _isGridView = true)),
          _ViewToggle(icon: Icons.view_list_rounded, active: !_isGridView, onTap: () => setState(() => _isGridView = false)),
        ]),
      ),
      _ActionButton(icon: Icons.create_new_folder_rounded, label: 'New Folder', onPressed: () => _showNewFolderDialog(context)),
      _ActionButton(icon: Icons.upload_file_rounded, label: 'Upload', primary: true, onPressed: () => _handleUpload(context)),
    ]);
  }

  Widget _buildLoadingSkeleton(bool isWide) {
    return Padding(
      padding: EdgeInsets.all(isWide ? 24 : 16),
      child: Column(children: List.generate(6, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const SizedBox(width: 16),
            Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 120, height: 12, decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 6),
              Container(width: 60, height: 10, decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(4))),
            ])),
          ]),
        ),
      ))),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.error),
        ),
        const SizedBox(height: 20),
        const Text('Something went wrong', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: AppTheme.textMuted, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => context.read<FileBloc>().add(FilesLoadRequested(folderId: _currentFolderId)),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ])),
    );
  }

  void _handleItemTap(BuildContext context, Map<String, dynamic> entry) {
    if (entry['entry_type'] == 'folder') {
      _currentFolderId = entry['id'];
      context.read<FileBloc>().add(FilesLoadRequested(folderId: entry['id']));
    }
  }

  void _handleAction(BuildContext context, Map<String, dynamic> entry, String action) {
    switch (action) {
      case 'rename': _showRenameDialog(context, entry); break;
      case 'delete': context.read<FileBloc>().add(FileDeleteRequested(entry['id'])); break;
      case 'download':
        final api = getIt<ApiClient>();
        final url = '${api.dio.options.baseUrl}api/v1/files/${entry['id']}/download';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.download_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Download: ${entry['name']}')),
          ]),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(label: 'Open', textColor: Colors.white, onPressed: () {}),
        ));
        break;
      case 'share':
        final api = getIt<ApiClient>();
        final url = '${api.dio.options.baseUrl}api/v1/files/${entry['id']}/download';
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.link_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Link copied to clipboard'),
          ]),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        break;
    }
  }

  void _handleUpload(BuildContext context) {
    platform.pickAndUploadFiles(context, _currentFolderId);
  }

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.create_new_folder_rounded, size: 20, color: AppTheme.primary)),
            const SizedBox(width: 12),
            const Text('New Folder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 20),
          TextField(controller: controller, decoration: const InputDecoration(labelText: 'Folder name', hintText: 'e.g. Documents', prefixIcon: Icon(Icons.folder_outlined, size: 20)), autofocus: true,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                context.read<FileBloc>().add(FolderCreateRequested(name: value.trim(), parentId: _currentFolderId));
                Navigator.pop(ctx);
              }
            },
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<FileBloc>().add(FolderCreateRequested(name: controller.text.trim(), parentId: _currentFolderId));
                Navigator.pop(ctx);
              }
            }, child: const Text('Create')),
          ]),
        ])),
      ),
    ));
  }

  void _showRenameDialog(BuildContext context, Map<String, dynamic> entry) {
    final controller = TextEditingController(text: entry['name'] ?? '');
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.edit_rounded, size: 20, color: AppTheme.accent)),
            const SizedBox(width: 12),
            const Text('Rename', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 20),
          TextField(controller: controller, decoration: const InputDecoration(labelText: 'New name', prefixIcon: Icon(Icons.text_fields_rounded, size: 20)), autofocus: true,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                context.read<FileBloc>().add(FileRenameRequested(itemId: entry['id'], newName: value.trim()));
                Navigator.pop(ctx);
              }
            },
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<FileBloc>().add(FileRenameRequested(itemId: entry['id'], newName: controller.text.trim()));
                Navigator.pop(ctx);
              }
            }, child: const Text('Rename')),
          ]),
        ])),
      ),
    ));
  }
}

// ─── Shared utility ─────────────────────────────────────
String formatFileSize(dynamic bytes) {
  final b = (bytes is int) ? bytes.toDouble() : 0.0;
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(1)} GB';
}

// ─── Sub-widgets ────────────────────────────────────────
class _ViewToggle extends StatelessWidget {
  final IconData icon; final bool active; final VoidCallback onTap;
  const _ViewToggle({required this.icon, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: active ? '' : (icon == Icons.grid_view_rounded ? 'Grid view' : 'List view'),
    child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: active ? AppTheme.primary.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 20, color: active ? AppTheme.primary : AppTheme.textMuted),
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onPressed; final bool primary;
  const _ActionButton({required this.icon, required this.label, required this.onPressed, this.primary = false});
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label))
      : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label));
}

class _Breadcrumb extends StatelessWidget {
  final List<Map<String, dynamic>> items; final Function(String?) onTap;
  const _Breadcrumb({required this.items, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          InkWell(onTap: () => onTap(null), borderRadius: BorderRadius.circular(6),
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(Icons.home_rounded, size: 16, color: AppTheme.primary))),
          for (int i = 0; i < items.length; i++) ...[
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.textMuted)),
            InkWell(
              onTap: () => onTap(items[i]['id']?.toString()),
              borderRadius: BorderRadius.circular(6),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(items[i]['name'] ?? 'Root', style: TextStyle(fontSize: 13, color: i == items.length - 1 ? AppTheme.textPrimary : AppTheme.primary, fontWeight: i == items.length - 1 ? FontWeight.w600 : FontWeight.normal))),
            ),
          ],
        ]),
      ),
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  final VoidCallback onUpload; final VoidCallback onNewFolder;
  const _EmptyFolder({required this.onUpload, required this.onNewFolder});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(48),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border, style: BorderStyle.solid)),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.primary.withOpacity(0.15), AppTheme.accent.withOpacity(0.1)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.cloud_upload_rounded, size: 48, color: AppTheme.primary),
      ),
      const SizedBox(height: 24),
      const Text('Drop files here or get started', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 8),
      const Text('Upload files or create folders to organize your cloud', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        OutlinedButton.icon(onPressed: onNewFolder, icon: const Icon(Icons.create_new_folder_rounded, size: 18), label: const Text('New Folder')),
        const SizedBox(width: 12),
        FilledButton.icon(onPressed: onUpload, icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Upload Files')),
      ]),
    ]),
  );
}

class _FileGridCard extends StatelessWidget {
  final Map<String, dynamic> entry; final VoidCallback onTap; final Function(String) onAction;
  const _FileGridCard({required this.entry, required this.onTap, required this.onAction});

  IconData _icon() {
    if (entry['entry_type'] == 'folder') return Icons.folder_rounded;
    final mime = (entry['mime_type'] ?? '').toString();
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.videocam_rounded;
    if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mime.contains('zip') || mime.contains('tar') || mime.contains('rar')) return Icons.archive_rounded;
    if (mime.contains('text') || mime.contains('document')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _iconColor() => entry['entry_type'] == 'folder' ? const Color(0xFFFFC107) : AppTheme.primary;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface, borderRadius: BorderRadius.circular(14),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
      hoverColor: AppTheme.primary.withOpacity(0.04),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _iconColor().withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(_icon(), size: 24, color: _iconColor())),
            PopupMenuButton<String>(onSelected: onAction, icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textMuted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: AppTheme.surface,
              itemBuilder: (_) => [
                if (entry['entry_type'] == 'file')
                  const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Download')])),
                if (entry['entry_type'] == 'file')
                  const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.link_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Copy Link')])),
                const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Rename')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error), SizedBox(width: 8), Text('Move to Trash', style: TextStyle(color: AppTheme.error))])),
              ]),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: double.infinity,
              child: Text(entry['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (entry['entry_type'] == 'file') Text(formatFileSize(entry['size_bytes'] ?? 0), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ]),
        ]),
      ),
    ),
  );
}

class _FileList extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final Function(Map<String, dynamic>) onTap;
  final Function(Map<String, dynamic>, String) onAction;
  const _FileList({required this.entries, required this.onTap, required this.onAction});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(children: [
      // Header
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: const Row(children: [
          Expanded(flex: 4, child: Text('Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted))),
          Expanded(flex: 2, child: Text('Size', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted))),
          Expanded(flex: 2, child: Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted))),
          SizedBox(width: 40),
        ])),
      ...entries.map((e) => Material(
        color: Colors.transparent,
        child: InkWell(onTap: () => onTap(e),
          hoverColor: AppTheme.primary.withOpacity(0.04),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5))),
            child: Row(children: [
              Expanded(flex: 4, child: Row(children: [
                Icon(e['entry_type'] == 'folder' ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                  size: 20, color: e['entry_type'] == 'folder' ? const Color(0xFFFFC107) : AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(e['name'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis)),
              ])),
              Expanded(flex: 2, child: Text(e['entry_type'] == 'folder' ? '--' : formatFileSize(e['size_bytes'] ?? 0),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
              Expanded(flex: 2, child: Text(e['mime_type'] ?? e['entry_type'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
              PopupMenuButton<String>(onSelected: (a) => onAction(e, a), icon: const Icon(Icons.more_vert_rounded, size: 16, color: AppTheme.textMuted),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: AppTheme.surface,
                itemBuilder: (_) => [
                  if (e['entry_type'] == 'file')
                    const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Download')])),
                  if (e['entry_type'] == 'file')
                    const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.link_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Copy Link')])),
                  const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit_rounded, size: 16, color: AppTheme.textMuted), SizedBox(width: 8), Text('Rename')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error), SizedBox(width: 8), Text('Move to Trash', style: TextStyle(color: AppTheme.error))])),
                ]),
            ])),
          ),
        ),
      ),
    ]),
  );
}
