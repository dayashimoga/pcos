import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;

  // Filters
  String _typeFilter = 'all'; // all, file, folder
  String _sortBy = 'relevance'; // relevance, name, size

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final api = getIt<ApiClient>();
      final params = <String, dynamic>{'q': q};
      if (_typeFilter != 'all') params['type'] = _typeFilter;
      final resp = await api.dio.get('/api/v1/search', queryParameters: params);
      setState(() {
        _results = List<Map<String, dynamic>>.from(resp.data['results'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Search failed: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredResults {
    var list = List<Map<String, dynamic>>.from(_results);
    if (_sortBy == 'name') {
      list.sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    } else if (_sortBy == 'size') {
      list.sort((a, b) => ((b['size_bytes'] ?? 0) as int)
          .compareTo((a['size_bytes'] ?? 0) as int));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredResults;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Search', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        Text('Find files across your cloud',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // Search bar
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: TextField(
            controller: _controller,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search files, folders...',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppTheme.textMuted),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: AppTheme.primary),
                onPressed: _search,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Filter chips
        Wrap(spacing: 8, runSpacing: 8, children: [
          _FilterChip(
              label: 'All',
              selected: _typeFilter == 'all',
              onTap: () {
                setState(() => _typeFilter = 'all');
                if (_searched) _search();
              }),
          _FilterChip(
              label: 'Files',
              icon: Icons.insert_drive_file_rounded,
              selected: _typeFilter == 'file',
              onTap: () {
                setState(() => _typeFilter = 'file');
                if (_searched) _search();
              }),
          _FilterChip(
              label: 'Folders',
              icon: Icons.folder_rounded,
              selected: _typeFilter == 'folder',
              onTap: () {
                setState(() => _typeFilter = 'folder');
                if (_searched) _search();
              }),
          const SizedBox(width: 8),
          _FilterChip(
              label: 'By Name',
              icon: Icons.sort_by_alpha_rounded,
              selected: _sortBy == 'name',
              onTap: () => setState(
                  () => _sortBy = _sortBy == 'name' ? 'relevance' : 'name')),
          _FilterChip(
              label: 'By Size',
              icon: Icons.storage_rounded,
              selected: _sortBy == 'size',
              onTap: () => setState(
                  () => _sortBy = _sortBy == 'size' ? 'relevance' : 'size')),
        ]),
        const SizedBox(height: 20),

        // Results
        if (_loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator())),
        if (!_loading && _searched && results.isEmpty)
          Container(
            padding: const EdgeInsets.all(48),
            width: double.infinity,
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context))),
            child: Column(children: [
              Icon(Icons.search_off_rounded,
                  size: 48, color: AppTheme.textMutedColor(context).withOpacity(0.5)),
              const SizedBox(height: 16),
              Text('No results found',
                  style: TextStyle(fontSize: 16, color: AppTheme.textMutedColor(context))),
              const SizedBox(height: 8),
              Text('Try different keywords or filters',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMutedColor(context).withOpacity(0.7))),
            ]),
          ),
        if (!_loading && results.isNotEmpty)
          Container(
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderColor(context))),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${results.length} result${results.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context),
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _sortBy == 'relevance'
                            ? 'By relevance'
                            : _sortBy == 'name'
                                ? 'A → Z'
                                : 'Largest first',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMutedColor(context)),
                      ),
                    ]),
              ),
              ...results.map((e) => ListTile(
                    leading: Icon(
                      e['entry_type'] == 'folder'
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded,
                      color: e['entry_type'] == 'folder'
                          ? const Color(0xFFFFC107)
                          : AppTheme.primary,
                    ),
                    title: Text(e['name'] ?? '',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textPrimaryColor(context))),
                    subtitle: Text(
                      e['entry_type'] == 'file'
                          ? formatFileSize(e['size_bytes'] ?? 0)
                          : 'Folder',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMutedColor(context)),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (e['entry_type'] == 'file')
                        IconButton(
                          icon: Icon(Icons.link_rounded,
                              size: 18, color: AppTheme.textMutedColor(context)),
                          tooltip: 'Copy link',
                          onPressed: () {
                            final api = getIt<ApiClient>();
                            final url =
                                '${api.dio.options.baseUrl}api/v1/files/${e['id']}/download';
                            Clipboard.setData(ClipboardData(text: url));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: const Text('Link copied'),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                          },
                        ),
                      if (e['entry_type'] == 'file')
                        IconButton(
                          icon: const Icon(Icons.download_rounded,
                              size: 20, color: AppTheme.primary),
                          tooltip: 'Download',
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Download: ${e['name']}'),
                              backgroundColor: AppTheme.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                          },
                        ),
                    ]),
                  )),
            ]),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withOpacity(0.15)
                  : AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.borderColor(context)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? AppTheme.primary : AppTheme.textMutedColor(context)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTheme.primary : AppTheme.textMutedColor(context))),
            ]),
          ),
        ),
      );
}
