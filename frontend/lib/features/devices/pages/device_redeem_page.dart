import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// Instant Device Pairing Redemption Page — handles QR scan link /#/pair?code=XXXXXX
class DeviceRedeemPage extends StatefulWidget {
  final String code;
  final String? serverUrl;

  const DeviceRedeemPage({super.key, required this.code, this.serverUrl});

  @override
  State<DeviceRedeemPage> createState() => _DeviceRedeemPageState();
}

class _DeviceRedeemPageState extends State<DeviceRedeemPage> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _serverCtrl;
  bool _pairing = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.code);
    final api = getIt<ApiClient>();
    _serverCtrl = TextEditingController(
      text: widget.serverUrl ?? api.currentServerUrl,
    );

    if (widget.code.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptRedeem();
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _attemptRedeem() async {
    final code = _codeCtrl.text.trim().replaceAll(' ', '');
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a 6-digit pairing code.');
      return;
    }

    setState(() {
      _pairing = true;
      _error = null;
      _success = false;
    });

    try {
      final api = getIt<ApiClient>();
      await api.redeemPairingCode(code, serverUrl: _serverCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _success = true;
      });

      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _success = false;
        _error = ApiClient.formatError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 4,
              color: AppTheme.surfaceColor(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppTheme.borderColor(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _success
                            ? AppTheme.success.withOpacity(0.15)
                            : AppTheme.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _success
                            ? Icons.check_circle_rounded
                            : Icons.qr_code_scanner_rounded,
                        size: 32,
                        color: _success ? AppTheme.success : AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _success
                          ? 'Device Paired!'
                          : (_pairing
                              ? 'Pairing Device...'
                              : 'Connect to PCOS'),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryColor(context),
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _success
                          ? 'Your device is authenticated. Loading files...'
                          : 'Pairing code enrolls this device into your personal cloud.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_pairing) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                    ] else if (_success) ...[
                      const SizedBox(height: 16),
                      const Icon(Icons.cloud_done_rounded,
                          size: 48, color: AppTheme.success),
                      const SizedBox(height: 24),
                    ] else ...[
                      TextField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                        ),
                        decoration: InputDecoration(
                          labelText: '6-Digit Pairing Code',
                          hintText: '856408',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.pin_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _serverCtrl,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimaryColor(context)),
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'http://192.168.0.111',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.dns_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              final text = data?.text?.trim() ?? '';
                              if (text.isNotEmpty) {
                                if (text.contains('code=')) {
                                  final uri = Uri.tryParse(text);
                                  if (uri != null) {
                                    final c = uri.queryParameters['code'];
                                    if (c != null) _codeCtrl.text = c;
                                    _serverCtrl.text =
                                        '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';
                                  }
                                } else if (text.length == 6 &&
                                    int.tryParse(text) != null) {
                                  _codeCtrl.text = text;
                                }
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.paste_rounded, size: 16),
                            label: const Text('Paste from Clipboard'),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.error),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppTheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _attemptRedeem,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Pair & Open PCOS Cloud'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Back to Sign In'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
