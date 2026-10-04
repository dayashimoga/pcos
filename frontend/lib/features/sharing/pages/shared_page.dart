import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;

/// File Sharing, Public Links, and File Request Hub.
class SharedPage extends StatefulWidget {
  const SharedPage({super.key});

  @override
  State<SharedPage> createState() => _SharedPageState();
}

class _SharedPageState extends State<SharedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _shares = [];
  List<Map<String, dynamic>> _userFiles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShares();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/shares');
      final List rawShares = resp.data is Map && resp.data['shares'] is List
          ? resp.data['shares']
          : (resp.data is List ? resp.data : []);

      final filesResp = await api.dio.get('/api/v1/files');
      final List rawFiles =
          filesResp.data is Map && filesResp.data['entries'] is List
              ? filesResp.data['entries']
              : (filesResp.data is List ? filesResp.data : []);

      if (mounted) {
        setState(() {
          _shares = rawShares
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList();
          _userFiles = rawFiles
              .where((f) => f['entry_type'] != 'folder')
              .map((f) => Map<String, dynamic>.from(f as Map))
              .toList();
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

  void _showCreateShareDialog() {
    if (_userFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No files available to share. Upload a file first!')),
      );
      return;
    }

    String selectedFileId = _userFiles.first['id']?.toString() ?? '';
    final passwordCtrl = TextEditingController();
    final maxDownloadsCtrl = TextEditingController(text: '10');
    String expiryChoice = '7d';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.share_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Create Secure Share Link',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select File to Share',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedFileId,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.surfaceLightColor(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: _userFiles
                        .map((f) => DropdownMenuItem(
                              value: f['id']?.toString(),
                              child: Text(
                                '${f['name'] ?? 'File'} (${formatFileSize((f['size_bytes'] as num?)?.toInt() ?? 0)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (val) => setDialogState(
                        () => selectedFileId = val ?? selectedFileId),
                  ),
                  const SizedBox(height: 14),
                  Text('Optional Password Protection',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText:
                          'Leave empty for public access without password',
                      filled: true,
                      fillColor: AppTheme.surfaceLightColor(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Link Expiration',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMutedColor(context))),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: expiryChoice,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppTheme.surfaceLightColor(context),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: '1d', child: Text('1 Day')),
                                DropdownMenuItem(
                                    value: '7d', child: Text('7 Days')),
                                DropdownMenuItem(
                                    value: '30d', child: Text('30 Days')),
                                DropdownMenuItem(
                                    value: 'never', child: Text('Never')),
                              ],
                              onChanged: (val) => setDialogState(
                                  () => expiryChoice = val ?? '7d'),
                            ),
                          ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Max Downloads',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMutedColor(context))),
                            const SizedBox(height: 6),
                            TextField(
                              controller: maxDownloadsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppTheme.surfaceLightColor(context),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ]),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final password = passwordCtrl.text.trim();
                final maxDl = int.tryParse(maxDownloadsCtrl.text.trim()) ?? 10;
                DateTime? expiresAt;
                if (expiryChoice == '1d') {
                  expiresAt = DateTime.now().add(const Duration(days: 1));
                }
                if (expiryChoice == '7d') {
                  expiresAt = DateTime.now().add(const Duration(days: 7));
                }
                if (expiryChoice == '30d') {
                  expiresAt = DateTime.now().add(const Duration(days: 30));
                }

                Navigator.pop(ctx);
                try {
                  final api = getIt<ApiClient>();
                  final resp = await api.dio.post('/api/v1/shares', data: {
                    'file_id': selectedFileId,
                    'is_public': true,
                    if (password.isNotEmpty) 'password': password,
                    if (expiresAt != null)
                      'expires_at': expiresAt.toIso8601String(),
                    'max_downloads': maxDl,
                  });

                  final shareData = resp.data is Map ? resp.data : {};
                  final token = shareData['share_token'] ?? '';
                  final fullUrl = shareData['share_url'] ??
                      '${api.dio.options.baseUrl}/#/shared/$token';

                  _loadShares();

                  if (mounted) {
                    _showShareCreatedSuccess(fullUrl);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Failed to create share: ${ApiClient.formatError(e)}')),
                    );
                  }
                }
              },
              child: const Text('Create Link'),
            ),
          ],
        ),
      ),
    );
  }

  void _showShareCreatedSuccess(String shareUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Share Link Created!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(
                  data: shareUrl, size: 180, version: QrVersions.auto),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLightColor(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(shareUrl,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share URL copied to clipboard!')),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Copy Link'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeShare(String shareId, String fileName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revoke Share Link?'),
        content: Text(
            'Anyone with this link will immediately lose access to "$fileName".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke Link'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final api = getIt<ApiClient>();
      await api.dio.delete('/api/v1/shares/$shareId');
      _loadShares();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link revoked successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to revoke share: ${ApiClient.formatError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadShares,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shared & Public Links',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Manage public access links, expirations, and downloads with zero account required for recipients.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ]),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _showCreateShareDialog,
                  icon: const Icon(Icons.add_link_rounded, size: 20),
                  label: const Text('Share File'),
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

            // Shares List
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator()))
            else if (_shares.isEmpty)
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
                    child: const Icon(Icons.share_outlined,
                        size: 36, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 16),
                  const Text('No Active Share Links',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Share files securely with friends, clients, or colleagues using expirable password-protected links or QR codes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textMutedColor(context)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white),
                    onPressed: _showCreateShareDialog,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: const Text('Create Your First Share Link'),
                  ),
                ]),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _shares.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final s = _shares[idx];
                  final fileName =
                      s['file_name'] ?? 'File #${s['file_id'] ?? ''}';
                  final token = s['share_token'] ?? '';
                  final downloads = s['download_count'] ?? 0;
                  final maxDl = s['max_downloads'];
                  final expiresAt = s['expires_at'];
                  final isPw = s['password_hash'] != null;

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.link_rounded,
                                color: AppTheme.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fileName,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Token: $token',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            AppTheme.textMutedColor(context)),
                                  ),
                                ]),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            tooltip: 'Copy Link',
                            onPressed: () {
                              final api = getIt<ApiClient>();
                              final url =
                                  '${api.dio.options.baseUrl}/#/shared/$token';
                              Clipboard.setData(ClipboardData(text: url));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Share URL copied to clipboard!')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: AppTheme.error, size: 20),
                            tooltip: 'Revoke Share',
                            onPressed: () =>
                                _revokeShare(s['id'] ?? '', fileName),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Downloads: $downloads${maxDl != null ? ' / $maxDl' : ''}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isPw)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_rounded,
                                          size: 12, color: AppTheme.warning),
                                      SizedBox(width: 4),
                                      Text('Password Protected',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.warning,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                              ),
                            if (expiresAt != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceLightColor(context),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Expires: ${expiresAt.toString().split('T').first}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMutedColor(context)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
