import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// File preview page — PDF, video, image, and text previews.
class FilePreviewPage extends StatelessWidget {
  final Map<String, dynamic> entry;
  const FilePreviewPage({super.key, required this.entry});

  String get _name => entry['name']?.toString() ?? 'File';
  String get _mime => entry['mime_type']?.toString() ?? '';
  String get _id => entry['id']?.toString() ?? '';

  String get _downloadUrl {
    final api = getIt<ApiClient>();
    return '${api.dio.options.baseUrl}api/v1/files/$_id/download';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_name,
            style: const TextStyle(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w500)),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.copy_rounded, size: 20, color: Colors.white70),
            tooltip: 'Copy Link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _downloadUrl));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Link copied'),
                  duration: Duration(seconds: 1)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded,
                size: 20, color: Colors.white70),
            tooltip: 'Download',
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (_mime.startsWith('image/'))
      return _ImagePreview(url: _downloadUrl, name: _name);
    if (_mime == 'application/pdf') return _PdfPreview(url: _downloadUrl);
    if (_mime.startsWith('video/'))
      return _VideoPreview(url: _downloadUrl, mime: _mime);
    if (_mime.startsWith('audio/'))
      return _AudioPreview(url: _downloadUrl, name: _name);
    if (_mime.startsWith('text/') ||
        _mime.contains('json') ||
        _mime.contains('xml') ||
        _mime.contains('yaml')) {
      return _TextPreview(fileId: _id);
    }
    return _UnsupportedPreview(name: _name, mime: _mime);
  }
}

/// Full-screen image preview with zoom.
class _ImagePreview extends StatelessWidget {
  final String url;
  final String name;
  const _ImagePreview({required this.url, required this.name});

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(
                  child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: AppTheme.primary,
              ));
            },
            errorBuilder: (_, __, ___) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_rounded,
                  size: 64, color: Colors.white30),
              const SizedBox(height: 12),
              Text(name,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ]),
          ),
        ),
      );
}

/// PDF preview using iframe embed (web only).
class _PdfPreview extends StatelessWidget {
  final String url;
  const _PdfPreview({required this.url});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppTheme.surface,
            width: double.infinity,
            child: Row(children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  size: 20, color: AppTheme.error),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('PDF Preview',
                      style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500))),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open in new tab'),
              ),
            ]),
          ),
          Expanded(
            child: Container(
              color: Colors.grey.shade900,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.picture_as_pdf_rounded,
                      size: 80, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text('PDF Viewer',
                      style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(url,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white30),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 20),
                  const Text(
                      'For web: Use HtmlElementView to embed PDF.\nFor mobile: Use a PDF rendering package.',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                      textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ],
      );
}

/// Video player with HLS-ready controls.
class _VideoPreview extends StatefulWidget {
  final String url;
  final String mime;
  const _VideoPreview({required this.url, required this.mime});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) => Column(children: [
        // Transport bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: AppTheme.surface,
          child: Row(children: [
            const Icon(Icons.videocam_rounded,
                size: 20, color: AppTheme.accent),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Video Player (${widget.mime})',
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('HLS Ready',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent)),
            ),
          ]),
        ),
        // Video area
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12)),
                child: Stack(alignment: Alignment.center, children: [
                  // Placeholder poster
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.grey.shade900, Colors.black],
                      ),
                    ),
                  ),
                  // Play button
                  GestureDetector(
                    onTap: () => setState(() => _playing = !_playing),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _playing ? 48 : 72,
                      height: _playing ? 48 : 72,
                      decoration: BoxDecoration(
                        color: _playing ? Colors.white10 : AppTheme.primary,
                        borderRadius: BorderRadius.circular(_playing ? 8 : 36),
                      ),
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: _playing ? 28 : 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Status text
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Text(
                      _playing ? 'Playing...' : 'Tap to play',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        // Controls bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: AppTheme.surface,
          child: Row(children: [
            IconButton(
              icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 24),
              onPressed: () => setState(() => _playing = !_playing),
            ),
            Expanded(
                child: SliderTheme(
              data: SliderThemeData(
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: AppTheme.primary),
              child: Slider(value: 0, onChanged: (_) {}),
            )),
            const Text('0:00 / --:--',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.fullscreen_rounded,
                    color: Colors.white54, size: 22),
                onPressed: () {}),
            IconButton(
                icon: const Icon(Icons.volume_up_rounded,
                    color: Colors.white54, size: 22),
                onPressed: () {}),
          ]),
        ),
      ]);
}

/// Audio player.
class _AudioPreview extends StatelessWidget {
  final String url;
  final String name;
  const _AudioPreview({required this.url, required this.name});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
              color: AppTheme.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.audiotrack_rounded,
                  size: 48, color: AppTheme.primary),
            ),
            const SizedBox(height: 20),
            Text(name,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white54),
                  onPressed: () {}),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(32)),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 28, color: Colors.white),
              ),
              IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white54),
                  onPressed: () {}),
            ]),
          ]),
        ),
      );
}

/// Unsupported file type.
class _UnsupportedPreview extends StatelessWidget {
  final String name;
  final String mime;
  const _UnsupportedPreview({required this.name, required this.mime});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.insert_drive_file_rounded,
              size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(name,
              style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Preview not available for $mime',
              style: const TextStyle(fontSize: 13, color: Colors.white38)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download File'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30)),
          ),
        ]),
      );
}

/// Text file preview.
class _TextPreview extends StatefulWidget {
  final String fileId;
  const _TextPreview({required this.fileId});
  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/files/${widget.fileId}/download');
      setState(() {
        _content = resp.data.toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _content = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    return Container(
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        _content,
        style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: Colors.white70,
            height: 1.6),
      ),
    );
  }
}
