import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/file_preview_page.dart';

/// Photo Gallery — timeline view of all images in the user's cloud.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio
          .get('/api/v1/search', queryParameters: {'q': '*', 'type': 'file'});
      final results =
          List<Map<String, dynamic>>.from(resp.data['results'] ?? []);
      // Filter images and sort by date descending
      _photos = results
          .where((f) => (f['mime_type'] ?? '').toString().startsWith('image/'))
          .toList()
        ..sort(
            (a, b) => (b['updated_at'] ?? '').compareTo(a['updated_at'] ?? ''));
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Group photos by month (e.g. "August 2026")
  Map<String, List<Map<String, dynamic>>> get _grouped {
    final groups = <String, List<Map<String, dynamic>>>{};
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    for (final p in _photos) {
      final date =
          p['updated_at']?.toString() ?? p['created_at']?.toString() ?? '';
      String key = 'Unknown';
      if (date.length >= 7) {
        try {
          final dt = DateTime.parse(date);
          key = '${months[dt.month - 1]} ${dt.year}';
        } catch (_) {}
      }
      groups.putIfAbsent(key, () => []).add(p);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final crossCount = isWide ? 5 : 3;

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Padding(
          padding: EdgeInsets.fromLTRB(
              isWide ? 24 : 16, isWide ? 24 : 16, isWide ? 24 : 16, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Gallery',
                        style: Theme.of(context).textTheme.displayMedium),
                    const SizedBox(height: 4),
                    Text('${_photos.length} photos',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ])),
              // View mode options
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderColor(context))),
                child: Row(children: [
                  const Icon(Icons.grid_view_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('${_photos.length}',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMutedColor(context),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
          ]),
        )),
        if (_loading)
          const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary)))
        else if (_error != null)
          SliverFillRemaining(
              child: Center(
                  child: Text('Error: $_error',
                      style: const TextStyle(color: AppTheme.error))))
        else if (_photos.isEmpty)
          SliverFillRemaining(
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceLightColor(context).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.photo_library_rounded,
                  size: 48, color: AppTheme.textMutedColor(context)),
            ),
            const SizedBox(height: 16),
            Text('No photos yet',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context))),
            const SizedBox(height: 8),
            Text('Upload images to see them here',
                style: TextStyle(color: AppTheme.textMutedColor(context))),
          ])))
        else
          ..._grouped.entries.expand((group) => [
                SliverToBoxAdapter(
                    child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      isWide ? 24 : 16, 20, isWide ? 24 : 16, 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(group.key,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 8),
                    Text('${group.value.length} photos',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textMutedColor(context))),
                  ]),
                )),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        mainAxisSpacing: 3,
                        crossAxisSpacing: 3),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _PhotoTile(photo: group.value[i]),
                      childCount: group.value.length,
                    ),
                  ),
                ),
              ]),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ]),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final Map<String, dynamic> photo;
  const _PhotoTile({required this.photo});

  @override
  Widget build(BuildContext context) {
    final api = getIt<ApiClient>();
    final url =
        '${api.dio.options.baseUrl}api/v1/files/${photo['id']}/download';

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FilePreviewPage(entry: photo),
          )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          cacheWidth: 300,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
                color: AppTheme.surfaceLightColor(context),
                child: const Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary)),
                ));
          },
          errorBuilder: (_, __, ___) => Container(
            color: AppTheme.surfaceLightColor(context),
            child: Center(
                child: Icon(Icons.broken_image_rounded,
                    size: 24, color: AppTheme.textMutedColor(context))),
          ),
        ),
      ),
    );
  }
}
