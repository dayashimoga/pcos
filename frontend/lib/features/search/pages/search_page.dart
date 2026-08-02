import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../pages/files_page.dart' show formatFileSize;

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

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _searched = true; });
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/search', queryParameters: {'q': q});
      setState(() {
        _results = List<Map<String, dynamic>>.from(resp.data['results'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Search', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        Text('Find files across your cloud', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // Search bar
        Container(
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
          child: TextField(
            controller: _controller,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search files, folders...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
              suffixIcon: IconButton(icon: const Icon(Icons.send_rounded, color: AppTheme.primary), onPressed: _search),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Results
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
        if (!_loading && _searched && _results.isEmpty)
          Container(
            padding: const EdgeInsets.all(48), width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              Icon(Icons.search_off_rounded, size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text('No results found', style: TextStyle(fontSize: 16, color: AppTheme.textMuted)),
            ]),
          ),
        if (!_loading && _results.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${_results.length} result${_results.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
              ),
              ..._results.map((e) => ListTile(
                leading: Icon(e['entry_type'] == 'folder' ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                  color: e['entry_type'] == 'folder' ? const Color(0xFFFFC107) : AppTheme.primary),
                title: Text(e['name'] ?? '', style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                subtitle: Text(e['entry_type'] == 'file' ? formatFileSize(e['size_bytes'] ?? 0) : 'Folder',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                trailing: e['entry_type'] == 'file'
                  ? IconButton(icon: const Icon(Icons.download_rounded, size: 20, color: AppTheme.primary),
                    onPressed: () {
                      final api = getIt<ApiClient>();
                      final url = '${api.dio.options.baseUrl}api/v1/files/${e['id']}/download';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download: $url')));
                    })
                  : null,
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
