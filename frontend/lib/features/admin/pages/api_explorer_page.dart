import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// Interactive REST API explorer for testing and documenting all PCOS API endpoints.
class ApiExplorerPage extends StatefulWidget {
  const ApiExplorerPage({super.key});

  @override
  State<ApiExplorerPage> createState() => _ApiExplorerPageState();
}

class _ApiExplorerPageState extends State<ApiExplorerPage> {
  String? _selectedEndpoint;
  String _responseBody = '';
  int _statusCode = 0;
  bool _loading = false;
  final _bodyCtrl = TextEditingController();

  static const _endpoints = <Map<String, String>>[
    // Auth
    {'method': 'POST', 'path': '/api/v1/auth/register', 'group': 'Auth'},
    {'method': 'POST', 'path': '/api/v1/auth/login', 'group': 'Auth'},
    {'method': 'POST', 'path': '/api/v1/auth/refresh', 'group': 'Auth'},
    {'method': 'POST', 'path': '/api/v1/auth/logout', 'group': 'Auth'},
    // Users
    {'method': 'GET', 'path': '/api/v1/users/me', 'group': 'Users'},
    {'method': 'PUT', 'path': '/api/v1/users/me', 'group': 'Users'},
    {'method': 'PUT', 'path': '/api/v1/users/me/password', 'group': 'Users'},
    // Files
    {'method': 'GET', 'path': '/api/v1/folders', 'group': 'Files'},
    {'method': 'POST', 'path': '/api/v1/folders', 'group': 'Files'},
    {'method': 'POST', 'path': '/api/v1/files/upload', 'group': 'Files'},
    {'method': 'GET', 'path': '/api/v1/files', 'group': 'Files'},
    {'method': 'DELETE', 'path': '/api/v1/files/:id', 'group': 'Files'},
    {'method': 'PUT', 'path': '/api/v1/files/:id', 'group': 'Files'},
    {'method': 'PUT', 'path': '/api/v1/files/:id/move', 'group': 'Files'},
    {'method': 'PUT', 'path': '/api/v1/files/:id/favorite', 'group': 'Files'},
    {'method': 'GET', 'path': '/api/v1/files/:id/download', 'group': 'Files'},
    {'method': 'POST', 'path': '/api/v1/files/bulk-delete', 'group': 'Files'},
    // Search
    {'method': 'GET', 'path': '/api/v1/search?q=*', 'group': 'Search'},
    {'method': 'POST', 'path': '/api/v1/search/reindex', 'group': 'Search'},
    // Shares
    {'method': 'GET', 'path': '/api/v1/shares', 'group': 'Shares'},
    {'method': 'POST', 'path': '/api/v1/shares', 'group': 'Shares'},
    // Devices
    {'method': 'GET', 'path': '/api/v1/devices', 'group': 'Devices'},
    {'method': 'POST', 'path': '/api/v1/devices/pair', 'group': 'Devices'},
    // Trash
    {'method': 'GET', 'path': '/api/v1/trash', 'group': 'Trash'},
    {'method': 'POST', 'path': '/api/v1/trash/empty', 'group': 'Trash'},
    // Notifications
    {
      'method': 'GET',
      'path': '/api/v1/notifications',
      'group': 'Notifications'
    },
    // Admin
    {'method': 'GET', 'path': '/api/v1/admin/users', 'group': 'Admin'},
    {'method': 'POST', 'path': '/api/v1/admin/users', 'group': 'Admin'},
    // Analytics
    {'method': 'GET', 'path': '/api/v1/analytics/stats', 'group': 'Analytics'},
    // Storage
    {'method': 'GET', 'path': '/api/v1/storage/stats', 'group': 'Storage'},
    // Version / Health
    {'method': 'GET', 'path': '/api/v1/version', 'group': 'System'},
    {'method': 'GET', 'path': '/health', 'group': 'System'},
  ];

  Color _methodColor(String method) {
    switch (method) {
      case 'GET':
        return const Color(0xFF4CAF50);
      case 'POST':
        return const Color(0xFF2196F3);
      case 'PUT':
        return const Color(0xFFFFA726);
      case 'DELETE':
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }

  Future<void> _executeRequest(Map<String, String> endpoint) async {
    setState(() {
      _loading = true;
      _responseBody = '';
      _statusCode = 0;
      _selectedEndpoint = endpoint['path'];
    });

    try {
      final api = getIt<ApiClient>();
      final method = endpoint['method']!;
      final path = endpoint['path']!;

      late final dynamic resp;
      switch (method) {
        case 'GET':
          resp = await api.dio.get(path);
          break;
        case 'POST':
          resp = await api.dio.post(path,
              data: _bodyCtrl.text.isNotEmpty ? _bodyCtrl.text : null);
          break;
        case 'PUT':
          resp = await api.dio.put(path,
              data: _bodyCtrl.text.isNotEmpty ? _bodyCtrl.text : null);
          break;
        case 'DELETE':
          resp = await api.dio.delete(path);
          break;
      }

      setState(() {
        _statusCode = resp.statusCode ?? 0;
        _responseBody = const JsonEncoder.withIndent('  ').convert(resp.data);
      });
    } catch (e) {
      setState(() {
        _statusCode = 0;
        _responseBody = ApiClient.formatError(e);
      });
    }

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    // Group endpoints
    final groups = <String, List<Map<String, String>>>{};
    for (final ep in _endpoints) {
      groups.putIfAbsent(ep['group']!, () => []).add(ep);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 24 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('API Explorer', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        Text('Test and explore all PCOS REST API endpoints',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // Two-column layout on desktop
        if (isWide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Endpoint list
            SizedBox(width: 360, child: _buildEndpointList(groups)),
            const SizedBox(width: 24),
            // Response panel
            Expanded(child: _buildResponsePanel()),
          ])
        else ...[
          _buildEndpointList(groups),
          const SizedBox(height: 16),
          _buildResponsePanel(),
        ],
      ]),
    );
  }

  Widget _buildEndpointList(Map<String, List<Map<String, String>>> groups) {
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Endpoints',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor(context))),
        ),
        ...groups.entries.expand((group) => [
              // Group header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: AppTheme.backgroundColor(context),
                child: Text(group.key,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMutedColor(context),
                        letterSpacing: 0.5)),
              ),
              // Endpoints
              ...group.value.map((ep) => Material(
                    color: _selectedEndpoint == ep['path']
                        ? AppTheme.primary.withOpacity(0.08)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => _executeRequest(ep),
                      hoverColor: AppTheme.primary.withOpacity(0.04),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(children: [
                          Container(
                            width: 52,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: _methodColor(ep['method']!)
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(ep['method']!,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _methodColor(ep['method']!)),
                                textAlign: TextAlign.center),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(ep['path']!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textPrimaryColor(context),
                                      fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ),
                  )),
            ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildResponsePanel() {
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderColor(context)))),
          child: Row(children: [
            const Icon(Icons.terminal_rounded,
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Response',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context))),
            const Spacer(),
            if (_statusCode > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _statusCode < 400
                        ? AppTheme.success.withOpacity(0.12)
                        : AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$_statusCode',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusCode < 400
                            ? AppTheme.success
                            : AppTheme.error)),
              ),
            if (_responseBody.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.copy_rounded,
                    size: 16, color: AppTheme.textMutedColor(context)),
                tooltip: 'Copy response',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _responseBody));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Response copied'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
                },
              ),
            ],
          ]),
        ),
        // Body
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_responseBody.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
                child: Text('Select an endpoint to send a request',
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 14))),
          )
        else
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(_responseBody,
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppTheme.textPrimaryColor(context))),
            ),
          ),
      ]),
    );
  }
}

class JsonEncoder {
  final String? indent;
  const JsonEncoder.withIndent(this.indent);

  String convert(dynamic data) {
    try {
      return _encode(data, 0);
    } catch (_) {
      return data.toString();
    }
  }

  String _encode(dynamic value, int depth) {
    final prefix = indent != null ? indent! * depth : '';
    final nextPrefix = indent != null ? indent! * (depth + 1) : '';

    if (value == null) return 'null';
    if (value is bool || value is num) return value.toString();
    if (value is String) return '"${value.replaceAll('"', '\\"')}"';

    if (value is List) {
      if (value.isEmpty) return '[]';
      final items =
          value.map((e) => '$nextPrefix${_encode(e, depth + 1)}').join(',\n');
      return '[\n$items\n$prefix]';
    }

    if (value is Map) {
      if (value.isEmpty) return '{}';
      final entries = value.entries
          .map((e) => '$nextPrefix"${e.key}": ${_encode(e.value, depth + 1)}')
          .join(',\n');
      return '{\n$entries\n$prefix}';
    }

    return value.toString();
  }
}
