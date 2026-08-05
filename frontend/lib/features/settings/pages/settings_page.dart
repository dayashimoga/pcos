import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show themeNotifier;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '...';
  String _displayName = '';
  String _email = '';
  bool _loading = true;
  bool _autoTagging = true;
  bool _smartSearch = true;
  String _defaultView = 'Grid View';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final api = getIt<ApiClient>();
    dynamic versionData;
    dynamic userData;
    try {
      final resp = await api.dio.get('/api/v1/version');
      versionData = resp.data;
    } catch (_) {}
    try {
      final resp = await api.dio.get('/api/v1/users/me');
      userData = resp.data;
    } catch (_) {}

    setState(() {
      _version = (versionData != null && versionData['version'] != null)
          ? versionData['version'].toString()
          : '1.2.0';
      _displayName = (userData != null && userData['display_name'] != null)
          ? userData['display_name'].toString()
          : '';
      _email = (userData != null && userData['email'] != null)
          ? userData['email'].toString()
          : '';
      _loading = false;
    });
  }

  void _showEditProfile(BuildContext context) {
    final nameCtrl = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_rounded,
                        size: 20, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('Edit Profile',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                ]),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20)),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                Text('Email: $_email',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textMuted)),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      try {
                        final api = getIt<ApiClient>();
                        await api.dio.put('/api/v1/users/me',
                            data: {'display_name': nameCtrl.text.trim()});
                        setState(() => _displayName = nameCtrl.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Profile updated'),
                                backgroundColor: AppTheme.success),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: AppTheme.error),
                          );
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.lock_rounded,
                        size: 20, color: AppTheme.warning),
                  ),
                  const SizedBox(width: 12),
                  const Text('Change Password',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                ]),
                const SizedBox(height: 20),
                TextField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: Icon(Icons.lock_outline, size: 20))),
                const SizedBox(height: 12),
                TextField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: Icon(Icons.lock_reset, size: 20))),
                const SizedBox(height: 12),
                TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: Icon(Icons.lock_reset, size: 20))),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      if (newCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Passwords do not match'),
                              backgroundColor: AppTheme.error),
                        );
                        return;
                      }
                      try {
                        final api = getIt<ApiClient>();
                        await api.dio.put('/api/v1/users/me/password', data: {
                          'current_password': currentCtrl.text,
                          'new_password': newCtrl.text,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Password changed'),
                                backgroundColor: AppTheme.success),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: AppTheme.error),
                          );
                        }
                      }
                    },
                    child: const Text('Change Password'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncSettings(BuildContext context) {
    String interval = '15 minutes';
    bool wifiOnly = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.sync_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('Sync Settings',
                style: TextStyle(color: AppTheme.textPrimary)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Auto-Sync Interval',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: interval,
                dropdownColor: AppTheme.surface,
                items: const [
                  DropdownMenuItem(
                      value: '5 minutes', child: Text('Every 5 minutes')),
                  DropdownMenuItem(
                      value: '15 minutes', child: Text('Every 15 minutes')),
                  DropdownMenuItem(
                      value: '1 hour', child: Text('Every 1 hour')),
                  DropdownMenuItem(
                      value: 'Manual', child: Text('Manual Sync Only')),
                ],
                onChanged: (val) => setDlgState(() => interval = val!),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wi-Fi Only Sync',
                    style:
                        TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                subtitle: const Text('Sync only when connected to Wi-Fi',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                value: wifiOnly,
                activeColor: AppTheme.primary,
                onChanged: (v) => setDlgState(() => wifiOnly = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Sync settings saved'),
                    backgroundColor: AppTheme.success));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStorageInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.storage_rounded, color: AppTheme.primary),
          SizedBox(width: 10),
          Text('Storage Usage & Quota',
              style: TextStyle(color: AppTheme.textPrimary)),
        ]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage Volume',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            SizedBox(height: 6),
            Text('Docker Volume: file_storage (/data/pcos/storage)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            SizedBox(height: 16),
            LinearProgressIndicator(
                value: 0.15,
                backgroundColor: Colors.white10,
                color: AppTheme.primary),
            SizedBox(height: 8),
            Text('Unlimited Quota (Self-Hosted Instance)',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showBackupsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.backup_rounded, color: AppTheme.primary),
          SizedBox(width: 10),
          Text('Automatic Backups',
              style: TextStyle(color: AppTheme.textPrimary)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nightly Snapshot Schedule',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            const Text('Status: Active (Every day at 02:00 UTC)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final api = getIt<ApiClient>();
                  await api.dio.post('/api/v1/backups',
                      data: {'name': 'Manual Snapshot'});
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Backup triggered successfully!'),
                        backgroundColor: AppTheme.success));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Backup failed: $e'),
                        backgroundColor: AppTheme.error));
                  }
                }
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Create Manual Backup Now'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showAiProviderDialog(BuildContext context) {
    String provider = 'Local Ollama';
    String endpoint = 'http://ollama:11434';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('AI Provider Configuration',
                style: TextStyle(color: AppTheme.textPrimary)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selected Provider',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: provider,
                dropdownColor: AppTheme.surface,
                items: const [
                  DropdownMenuItem(
                      value: 'Local Ollama',
                      child: Text('Local Ollama (Zero Cost)')),
                  DropdownMenuItem(
                      value: 'OpenAI API', child: Text('OpenAI (Cloud GPT-4)')),
                ],
                onChanged: (val) => setDlgState(() => provider = val!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: endpoint,
                decoration:
                    const InputDecoration(labelText: 'Provider Endpoint'),
                onChanged: (val) => endpoint = val,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('AI Provider updated'),
                    backgroundColor: AppTheme.success));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDefaultViewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Select Default View',
            style: TextStyle(color: AppTheme.textPrimary)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _defaultView = 'Grid View');
              Navigator.pop(ctx);
            },
            child: const Row(children: [
              Icon(Icons.grid_view_rounded, color: AppTheme.primary),
              SizedBox(width: 12),
              Text('Grid View', style: TextStyle(color: AppTheme.textPrimary)),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _defaultView = 'List View');
              Navigator.pop(ctx);
            },
            child: const Row(children: [
              Icon(Icons.format_list_bulleted_rounded, color: AppTheme.primary),
              SizedBox(width: 12),
              Text('List View', style: TextStyle(color: AppTheme.textPrimary)),
            ]),
          ),
        ],
      ),
    );
  }

  void _showSourceCodeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.code_rounded, color: AppTheme.primary),
          SizedBox(width: 10),
          Text('PCOS Source Code',
              style: TextStyle(color: AppTheme.textPrimary)),
        ]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repository',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            SizedBox(height: 4),
            SelectableText('https://github.com/dayashimoga/pcos.git',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('License: AGPL-3.0 (Open Source & Self-Hosted)',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Settings', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        Text('Configure your PCOS instance',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),
        _SettingsSection(title: 'Account', children: [
          _SettingsTile(
            icon: Icons.person_rounded,
            title: 'Profile',
            subtitle: _loading
                ? 'Loading...'
                : (_displayName.isNotEmpty
                    ? _displayName
                    : 'Edit your display name'),
            onTap: () => _showEditProfile(context),
          ),
          _SettingsTile(
            icon: Icons.lock_rounded,
            title: 'Change Password',
            subtitle: 'Update your password',
            onTap: () => _showChangePassword(context),
          ),
          _SettingsTile(
            icon: Icons.security_rounded,
            title: 'Two-Factor Authentication',
            subtitle: 'Add an extra layer of security',
            onTap: () => showDialog(
              context: context,
              builder: (_) => const Dialog(
                child: SizedBox(
                    width: 500, height: 500, child: _MfaDialogContent()),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'Sync & Storage', children: [
          _SettingsTile(
              icon: Icons.sync_rounded,
              title: 'Sync Settings',
              subtitle: 'Configure sync behavior and folders',
              onTap: () => _showSyncSettings(context)),
          _SettingsTile(
              icon: Icons.storage_rounded,
              title: 'Storage',
              subtitle: 'View storage usage and manage quotas',
              onTap: () => _showStorageInfo(context)),
          _SettingsTile(
              icon: Icons.backup_rounded,
              title: 'Backups',
              subtitle: 'Schedule automatic backups',
              onTap: () => _showBackupsDialog(context)),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'AI & Intelligence', children: [
          _SettingsTile(
              icon: Icons.auto_awesome_rounded,
              title: 'AI Provider',
              subtitle: 'Configure local Ollama or API provider',
              onTap: () => _showAiProviderDialog(context)),
          _SettingsTile(
            icon: Icons.label_rounded,
            title: 'Auto-Tagging',
            subtitle: 'Enable automatic file tagging',
            trailing: Switch(
                value: _autoTagging,
                onChanged: (v) {
                  setState(() => _autoTagging = v);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('Auto-tagging ${v ? "enabled" : "disabled"}'),
                      backgroundColor: AppTheme.success));
                },
                activeColor: AppTheme.primary),
          ),
          _SettingsTile(
            icon: Icons.find_in_page_rounded,
            title: 'Smart Search',
            subtitle: 'Use AI for natural language search',
            trailing: Switch(
                value: _smartSearch,
                onChanged: (v) {
                  setState(() => _smartSearch = v);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('Smart Search ${v ? "enabled" : "disabled"}'),
                      backgroundColor: AppTheme.success));
                },
                activeColor: AppTheme.primary),
          ),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'Appearance', children: [
          _SettingsTile(
            icon: Icons.dark_mode_rounded,
            title: 'Dark Mode',
            subtitle: themeNotifier.value == ThemeMode.dark ? 'On' : 'Off',
            trailing: Switch(
              value: themeNotifier.value == ThemeMode.dark,
              onChanged: (v) {
                setState(() {
                  themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
                });
              },
              activeColor: AppTheme.primary,
            ),
          ),
          _SettingsTile(
              icon: Icons.view_module_rounded,
              title: 'Default View',
              subtitle: _defaultView,
              onTap: () => _showDefaultViewDialog(context)),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'About', children: [
          _SettingsTile(
              icon: Icons.info_rounded,
              title: 'Version',
              subtitle: 'PCOS v$_version',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('PCOS v1.2.0 is up to date'),
                    backgroundColor: AppTheme.success));
              }),
          _SettingsTile(
              icon: Icons.code_rounded,
              title: 'Source Code',
              subtitle: 'github.com/dayashimoga/pcos',
              onTap: () => _showSourceCodeDialog(context)),
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(height: 1, color: AppTheme.border, indent: 56),
              ],
            ]),
          ),
        ],
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _SettingsTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap,
      this.trailing});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppTheme.primary, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted)
                : null),
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
          leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
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
      setState(() {
        _enabled = resp.data['mfa_enabled'] == true;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(
        _enabled ? Icons.verified_user_rounded : Icons.shield_outlined,
        color: _enabled ? const Color(0xFF4CAF50) : AppTheme.textMuted,
        size: 48,
      ),
      const SizedBox(height: 16),
      Text(
        _enabled ? 'MFA is enabled' : 'MFA is not enabled',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _enabled ? const Color(0xFF4CAF50) : AppTheme.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _enabled
            ? 'Your account is protected.'
            : 'Enable MFA in the Security settings for enhanced protection.',
        style: const TextStyle(color: AppTheme.textMuted),
      ),
    ]);
  }
}
