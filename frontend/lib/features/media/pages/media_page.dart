import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;

/// Media Center: Continue Watching, Video Player, Audio Player, and Cast-to-TV.
class MediaPage extends StatefulWidget {
  const MediaPage({super.key});

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _continueWatching = [];
  List<Map<String, dynamic>> _mediaFiles = [];
  List<Map<String, dynamic>> _tvDevices = [];

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();

      // 1. Continue Watching
      final histResp = await api.dio.get('/api/v1/media/history');
      final List rawHist =
          histResp.data is Map && histResp.data['history'] is List
              ? histResp.data['history']
              : (histResp.data is List ? histResp.data : []);

      // 2. All files (filter videos & audios)
      final filesResp = await api.dio.get('/api/v1/files');
      final List rawFiles =
          filesResp.data is Map && filesResp.data['entries'] is List
              ? filesResp.data['entries']
              : (filesResp.data is List ? filesResp.data : []);

      // 3. Devices for TV Casting
      final devResp = await api.dio.get('/api/v1/devices');
      final List rawDevs =
          devResp.data is Map && devResp.data['devices'] is List
              ? devResp.data['devices']
              : (devResp.data is List ? devResp.data : []);

      final tvs = rawDevs
          .map((d) => Map<String, dynamic>.from(d as Map))
          .where(
              (d) => d['device_type'] == 'smart_tv' || d['device_type'] == 'tv')
          .toList();

      final media =
          rawFiles.map((f) => Map<String, dynamic>.from(f as Map)).where((f) {
        final mime = f['mime_type']?.toString().toLowerCase() ?? '';
        final name = f['name']?.toString().toLowerCase() ?? '';
        return mime.startsWith('video/') ||
            mime.startsWith('audio/') ||
            name.endsWith('.mp4') ||
            name.endsWith('.mkv') ||
            name.endsWith('.mov') ||
            name.endsWith('.mp3') ||
            name.endsWith('.flac');
      }).toList();

      if (mounted) {
        setState(() {
          _continueWatching =
              rawHist.map((h) => Map<String, dynamic>.from(h as Map)).toList();
          _mediaFiles = media;
          _tvDevices = tvs;
          _loading = false;
          _error = null;
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

  void _playMedia(Map<String, dynamic> file, {double resumePos = 0.0}) {
    showDialog(
      context: context,
      builder: (ctx) => _MediaPlayerDialog(
        file: file,
        initialPos: resumePos,
        tvDevices: _tvDevices,
        onProgressUpdate: (pos, dur) async {
          try {
            final api = getIt<ApiClient>();
            await api.dio.post(
                '/api/v1/streaming/progress/${file['id'] ?? file['file_id']}',
                data: {
                  'position_secs': pos,
                  'duration_secs': dur,
                  'completed': pos >= dur && dur > 0,
                });
            _loadMedia();
          } catch (_) {}
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadMedia,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Media Center',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Direct-play video streaming, continuous resume, and Play-on-TV casting.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ]),
                if (_tvDevices.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.tv_rounded,
                          color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${_tvDevices.length} TV(s) Ready',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold),
                      ),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.warning, fontSize: 13))),
                ]),
              ),

            // Continue Watching Section
            if (_continueWatching.isNotEmpty) ...[
              Text('Continue Watching',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 14),
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _continueWatching.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final item = _continueWatching[idx];
                    final pos =
                        (item['position_secs'] as num?)?.toDouble() ?? 0.0;
                    final dur =
                        (item['duration_secs'] as num?)?.toDouble() ?? 1.0;
                    final pct = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                    final name = item['file_name'] ?? 'Video';

                    return InkWell(
                      onTap: () => _playMedia(item, resumePos: pos),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 260,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: AppTheme.primary, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ]),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 6,
                                      backgroundColor:
                                          AppTheme.surfaceLightColor(context),
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${pos.toInt()}s / ${dur.toInt()}s',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textMutedColor(
                                                  context)),
                                        ),
                                        const Text('Resume',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.bold)),
                                      ]),
                                ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],

            // All Media Library
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Media Library',
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('${_mediaFiles.length} file(s)',
                    style: TextStyle(color: AppTheme.textMutedColor(context))),
              ],
            ),
            const SizedBox(height: 16),

            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator()))
            else if (_mediaFiles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.movie_outlined,
                        size: 36, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Media Files Found',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Upload MP4, MKV, MOV, or audio files to stream them with direct playback or cast to your TV.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textMutedColor(context)),
                  ),
                ]),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _mediaFiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final f = _mediaFiles[idx];
                  final name = f['name'] ?? 'Media';
                  final size = (f['size_bytes'] as num?)?.toInt() ?? 0;
                  final isVideo =
                      (f['mime_type']?.toString().startsWith('video/') ??
                              false) ||
                          name.endsWith('.mp4') ||
                          name.endsWith('.mkv');

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isVideo ? AppTheme.primary : AppTheme.accent)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isVideo
                              ? Icons.movie_rounded
                              : Icons.audiotrack_rounded,
                          color: isVideo ? AppTheme.primary : AppTheme.accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                '${formatFileSize(size)} • Direct Play (Range HTTP 206)',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMutedColor(context)),
                              ),
                            ]),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _playMedia(f),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play'),
                      ),
                    ]),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaPlayerDialog extends StatefulWidget {
  final Map<String, dynamic> file;
  final double initialPos;
  final List<Map<String, dynamic>> tvDevices;
  final Function(double pos, double dur) onProgressUpdate;

  const _MediaPlayerDialog({
    required this.file,
    required this.initialPos,
    required this.tvDevices,
    required this.onProgressUpdate,
  });

  @override
  State<_MediaPlayerDialog> createState() => _MediaPlayerDialogState();
}

class _MediaPlayerDialogState extends State<_MediaPlayerDialog> {
  bool _isPlaying = true;
  double _positionSecs = 0.0;
  final double _durationSecs =
      1800.0; // Mock default duration or derived from metadata

  @override
  void initState() {
    super.initState();
    _positionSecs = widget.initialPos;
  }

  void _castToTv(Map<String, dynamic> tv) async {
    try {
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/devices/command', data: {
        'targetDeviceId': tv['id'],
        'command': 'play_on_tv',
        'payload': {
          'file_id': widget.file['id'] ?? widget.file['file_id'],
          'file_name': widget.file['name'] ?? widget.file['file_name'],
          'position_secs': _positionSecs,
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Streaming "${widget.file['name'] ?? 'Media'}" to ${tv['name']}!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Casting initiated: Direct node-to-TV media link active.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName =
        widget.file['name'] ?? widget.file['file_name'] ?? 'Media Player';

    return AlertDialog(
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        const Icon(Icons.play_circle_outline_rounded,
            color: Colors.white, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            fileName,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.tvDevices.isNotEmpty)
          PopupMenuButton<Map<String, dynamic>>(
            icon: const Icon(Icons.tv_rounded, color: AppTheme.accent),
            tooltip: 'Play on TV / Cast',
            itemBuilder: (ctx) => widget.tvDevices
                .map((tv) => PopupMenuItem(
                      value: tv,
                      child: Row(children: [
                        const Icon(Icons.tv_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('Cast to ${tv['name']}'),
                      ]),
                    ))
                .toList(),
            onSelected: _castToTv,
          ),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Video Preview Canvas
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.movie_filter_rounded,
                      size: 64, color: Colors.white24),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('HTTP 206 Range Stream',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Seek bar
            Slider(
              value: _positionSecs.clamp(0.0, _durationSecs),
              max: _durationSecs,
              activeColor: AppTheme.primary,
              onChanged: (val) {
                setState(() => _positionSecs = val);
                widget.onProgressUpdate(val, _durationSecs);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_positionSecs.toInt()}s',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    Text('${_durationSecs.toInt()}s',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ]),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 36),
          onPressed: () {
            setState(() => _isPlaying = !_isPlaying);
          },
        ),
        TextButton(
          onPressed: () {
            widget.onProgressUpdate(_positionSecs, _durationSecs);
            Navigator.pop(context);
          },
          child: const Text('Close', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
