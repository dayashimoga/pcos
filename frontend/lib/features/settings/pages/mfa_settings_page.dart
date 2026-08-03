import 'package:flutter/material.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class MfaSettingsPage extends StatefulWidget {
  const MfaSettingsPage({super.key});

  @override
  State<MfaSettingsPage> createState() => _MfaSettingsPageState();
}

class _MfaSettingsPageState extends State<MfaSettingsPage> {
  bool _mfaEnabled = false;
  String? _secret;
  String? _provisioningUri; // ignore: unused_field
  bool _loading = true;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/auth/mfa/status');
      setState(() { _mfaEnabled = resp.data['mfa_enabled'] == true; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

  Future<void> _setupMfa() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.post('/api/v1/auth/mfa/setup');
      setState(() {
        _secret = resp.data['secret'];
        _provisioningUri = resp.data['provisioning_uri'];
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Setup failed: $e')));
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.length != 6) return;
    try {
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/auth/mfa/verify', data: {'code': _codeController.text});
      setState(() { _mfaEnabled = true; _secret = null; _provisioningUri = null; });
      _codeController.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MFA enabled successfully!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code. Try again.')));
    }
  }

  Future<void> _disableMfa() async {
    final code = await showDialog<String>(context: context, builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Disable MFA'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Enter TOTP code'), keyboardType: TextInputType.number, maxLength: 6),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Disable'))],
      );
    });
    if (code == null || code.length != 6) return;
    try {
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/auth/mfa/disable', data: {'code': code});
      setState(() { _mfaEnabled = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MFA disabled')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed — invalid code')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Two-Factor Authentication', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text('Protect your account with TOTP-based MFA', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),

        // Status card
        Container(
          padding: const EdgeInsets.all(20), width: double.infinity,
          decoration: BoxDecoration(
            color: _mfaEnabled ? const Color(0xFF1a3a1a) : AppTheme.surface,
            borderRadius: BorderRadius.circular(14), border: Border.all(color: _mfaEnabled ? const Color(0xFF2d6a2d) : AppTheme.border),
          ),
          child: Row(children: [
            Icon(_mfaEnabled ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: _mfaEnabled ? const Color(0xFF4CAF50) : AppTheme.textMuted, size: 36),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_mfaEnabled ? 'MFA is Enabled' : 'MFA is Disabled',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _mfaEnabled ? const Color(0xFF4CAF50) : AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(_mfaEnabled ? 'Your account is protected with two-factor authentication.' : 'Enable MFA for enhanced security.',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ])),
            if (_mfaEnabled) TextButton(onPressed: _disableMfa, child: const Text('Disable', style: TextStyle(color: Color(0xFFEF5350)))),
            if (!_mfaEnabled && _secret == null) ElevatedButton(onPressed: _setupMfa, child: const Text('Enable MFA')),
          ]),
        ),

        // Setup flow
        if (_secret != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20), width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Step 1: Add to your authenticator app', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              const Text('Manual entry key:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF1a1a2e), borderRadius: BorderRadius.circular(8)),
                child: SelectableText(_secret!, style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary, letterSpacing: 3)),
              ),
              const SizedBox(height: 20),
              const Text('Step 2: Enter the 6-digit code', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(width: 200, child: TextField(
                  controller: _codeController, keyboardType: TextInputType.number, maxLength: 6,
                  decoration: const InputDecoration(hintText: '000000', counterText: '', border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 24, fontFamily: 'monospace', letterSpacing: 8),
                )),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: _verifyCode, child: const Text('Verify & Enable')),
              ]),
            ]),
          ),
        ],
      ],
    ));
  }

  @override
  void dispose() { _codeController.dispose(); super.dispose(); }
}
