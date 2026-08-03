import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Settings', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        Text('Configure your PCOS instance', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),

        _SettingsSection(title: 'Account', children: [
          _SettingsTile(icon: Icons.person_rounded, title: 'Profile', subtitle: 'Edit your display name and email', onTap: () {}),
          _SettingsTile(icon: Icons.lock_rounded, title: 'Change Password', subtitle: 'Update your password', onTap: () {}),
          _SettingsTile(icon: Icons.security_rounded, title: 'Two-Factor Authentication', subtitle: 'Add an extra layer of security',
            onTap: () => showDialog(context: context, builder: (_) => Dialog(
              child: SizedBox(width: 500, height: 500, child: const _MfaDialogContent())))),
        ]),
        const SizedBox(height: 24),

        _SettingsSection(title: 'Sync & Storage', children: [
          _SettingsTile(icon: Icons.sync_rounded, title: 'Sync Settings', subtitle: 'Configure sync behavior and folders', onTap: () {}),
          _SettingsTile(icon: Icons.storage_rounded, title: 'Storage', subtitle: 'View storage usage and manage quotas', onTap: () {}),
          _SettingsTile(icon: Icons.backup_rounded, title: 'Backups', subtitle: 'Schedule automatic backups', onTap: () {}),
        ]),
        const SizedBox(height: 24),

        _SettingsSection(title: 'AI & Intelligence', children: [
          _SettingsTile(icon: Icons.auto_awesome_rounded, title: 'AI Provider', subtitle: 'Configure local Ollama or API provider', onTap: () {}),
          _SettingsTile(icon: Icons.label_rounded, title: 'Auto-Tagging', subtitle: 'Enable automatic file tagging', trailing: Switch(value: true, onChanged: (_) {}, activeColor: AppTheme.primary)),
          _SettingsTile(icon: Icons.find_in_page_rounded, title: 'Smart Search', subtitle: 'Use AI for natural language search', trailing: Switch(value: true, onChanged: (_) {}, activeColor: AppTheme.primary)),
        ]),
        const SizedBox(height: 24),

        _SettingsSection(title: 'Appearance', children: [
          _SettingsTile(icon: Icons.dark_mode_rounded, title: 'Dark Mode', subtitle: 'Always on', trailing: Switch(value: true, onChanged: (_) {}, activeColor: AppTheme.primary)),
          _SettingsTile(icon: Icons.view_module_rounded, title: 'Default View', subtitle: 'Grid view for file browser', onTap: () {}),
        ]),
        const SizedBox(height: 24),

        _SettingsSection(title: 'About', children: [
          _SettingsTile(icon: Icons.info_rounded, title: 'Version', subtitle: 'PCOS v0.2.0'),
          _SettingsTile(icon: Icons.code_rounded, title: 'Source Code', subtitle: 'github.com/dayashimoga/pcos', onTap: () {}),
        ]),
      ]),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5)),
    const SizedBox(height: 12),
    Container(
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const Divider(height: 1, color: AppTheme.border, indent: 56),
        ],
      ]),
    ),
  ]);
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final VoidCallback? onTap; final Widget? trailing;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: AppTheme.primary, size: 20)),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
    trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted) : null),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class _MfaDialogContent extends StatelessWidget {
  const _MfaDialogContent();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Two-Factor Authentication'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          backgroundColor: AppTheme.surface,
        ),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: _InlineMfaContent(),
        ),
      ),
    );
  }
}

class _InlineMfaContent extends StatefulWidget {
  const _InlineMfaContent();
  @override
  State<_InlineMfaContent> createState() => _InlineMfaContentState();
}

class _InlineMfaContentState extends State<_InlineMfaContent> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/auth/mfa/status');
      setState(() { _enabled = resp.data['mfa_enabled'] == true; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(_enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
        color: _enabled ? const Color(0xFF4CAF50) : AppTheme.textMuted, size: 48),
      const SizedBox(height: 16),
      Text(_enabled ? 'MFA is enabled' : 'MFA is not enabled',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _enabled ? const Color(0xFF4CAF50) : AppTheme.textPrimary)),
      const SizedBox(height: 8),
      Text(_enabled ? 'Your account is protected.' : 'Enable MFA in the Security settings for enhanced protection.',
        style: const TextStyle(color: AppTheme.textMuted)),
    ]);
  }
}
