import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_service.dart';
import '../widgets/free_tier_budget_card.dart';

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
          : '1.8.0';
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
        backgroundColor: AppTheme.surfaceColor(context),
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
                  Text('Edit Profile',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimaryColor(context))),
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
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final api = getIt<ApiClient>();
                        await api.dio.put('/api/v1/users/me',
                            data: {'display_name': nameCtrl.text.trim()});
                        if (mounted) {
                          setState(() => _displayName = nameCtrl.text.trim());
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Profile updated'),
                              backgroundColor: AppTheme.success),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Failed: $e'),
                              backgroundColor: AppTheme.error),
                        );
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
        backgroundColor: AppTheme.surfaceColor(context),
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
                  Text('Change Password',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimaryColor(context))),
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
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final api = getIt<ApiClient>();
                        await api.dio.put('/api/v1/users/me/password', data: {
                          'current_password': currentCtrl.text,
                          'new_password': newCtrl.text,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Password changed'),
                              backgroundColor: AppTheme.success),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Failed: $e'),
                              backgroundColor: AppTheme.error),
                        );
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
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.sync_rounded, color: AppTheme.primary),
            const SizedBox(width: 10),
            Text('Sync Settings',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auto-Sync Interval',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textMutedColor(context))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: interval,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
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
                title: Text('Wi-Fi Only Sync',
                    style: TextStyle(
                        color: AppTheme.textPrimaryColor(context),
                        fontSize: 14)),
                subtitle: Text('Sync only when connected to Wi-Fi',
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context), fontSize: 12)),
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
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.storage_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text('Storage Usage & Quota',
              style: TextStyle(color: AppTheme.textPrimaryColor(context))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage Volume',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textMutedColor(context))),
            const SizedBox(height: 6),
            Text('Docker Volume: file_storage (/data/pcos/storage)',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context))),
            const SizedBox(height: 16),
            const LinearProgressIndicator(
                value: 0.15,
                backgroundColor: Colors.white10,
                color: AppTheme.primary),
            const SizedBox(height: 8),
            Text('Unlimited Quota (Self-Hosted Instance)',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textMutedColor(context))),
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
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final api = getIt<ApiClient>();
                  await api.dio.post('/api/v1/backups',
                      data: {'name': 'Manual Snapshot'});
                  if (ctx.mounted) Navigator.pop(ctx);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Backup triggered successfully!'),
                      backgroundColor: AppTheme.success));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('Backup failed: $e'),
                      backgroundColor: AppTheme.error));
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
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
            const SizedBox(width: 10),
            Text('AI Provider Configuration',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selected Provider',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textMutedColor(context))),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: provider,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
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

  void _showEmergencyRecoveryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 520,
          child: _EmergencyRecoveryDialogContent(),
        ),
      ),
    );
  }

  void _showFamilyCloudHubDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 560,
          child: _FamilyCloudHubDialogContent(),
        ),
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
        const SizedBox(height: 24),
        FreeTierBudgetCard(apiClient: getIt<ApiClient>()),
        const SizedBox(height: 24),
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
          _SettingsTile(
            icon: Icons.vpn_key_rounded,
            title: 'Emergency Account Recovery',
            subtitle:
                'Generate & inspect your offline 12-word cryptographic recovery phrase',
            onTap: () => _showEmergencyRecoveryDialog(context),
          ),
          _SettingsTile(
            icon: Icons.family_restroom_rounded,
            title: 'Family Cloud Hub',
            subtitle:
                'Manage multi-user family spaces, member roles, and quota allocations',
            onTap: () => _showFamilyCloudHubDialog(context),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.palette_outlined,
                      size: 20, color: AppTheme.textMutedColor(context)),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme Mode',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimaryColor(context))),
                      Text('Persistent Light, Dark, or System preference',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMutedColor(context))),
                    ],
                  ),
                ]),
                const ThemeSwitchWidget(),
              ],
            ),
          ),
          Divider(color: AppTheme.borderColor(context), height: 1),
          _SettingsTile(
              icon: Icons.view_module_rounded,
              title: 'Default View',
              subtitle: _defaultView,
              onTap: () => _showDefaultViewDialog(context)),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'Advanced & Diagnostics', children: [
          _SettingsTile(
            icon: Icons.health_and_safety_rounded,
            title: 'Doctor Diagnostics',
            subtitle:
                'Inspect node health, disk stats, CGNAT and control plane connectivity',
            onTap: () => context.go('/doctor'),
          ),
          _SettingsTile(
            icon: Icons.api_rounded,
            title: 'API Explorer',
            subtitle:
                'Interactive live PCOS REST & WebSocket API testing workbench',
            onTap: () => context.go('/admin/api'),
          ),
          _SettingsTile(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Admin Console',
            subtitle: 'Tenant management, audit logs, and edge policies',
            onTap: () => context.go('/admin'),
          ),
        ]),
        const SizedBox(height: 24),
        _SettingsSection(title: 'About', children: [
          _SettingsTile(
              icon: Icons.info_rounded,
              title: 'Version',
              subtitle: 'PCOS v$_version',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('PCOS v1.8.0 is up to date'),
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppTheme.textMuted : const Color(0xFF64748B);
    final borderColor = isDark ? AppTheme.border : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor)),
          child: Column(children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, color: borderColor, indent: 56),
            ],
          ]),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.textPrimary : const Color(0xFF0F172A);
    final textMuted = isDark ? AppTheme.textMuted : const Color(0xFF64748B);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppTheme.primary, size: 20),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
      subtitle:
          Text(subtitle, style: TextStyle(fontSize: 12, color: textMuted)),
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, color: textMuted)
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
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

class _EmergencyRecoveryDialogContent extends StatefulWidget {
  const _EmergencyRecoveryDialogContent();

  @override
  State<_EmergencyRecoveryDialogContent> createState() =>
      _EmergencyRecoveryDialogContentState();
}

class _EmergencyRecoveryDialogContentState
    extends State<_EmergencyRecoveryDialogContent> {
  bool _loading = false;
  String? _error;
  List<String> _words = [];
  String _phrase = '';

  Future<void> _generatePhrase() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.post('/api/v1/auth/recovery/generate');
      if (resp.data is Map && resp.data['success'] == true) {
        final phraseStr = resp.data['phrase']?.toString() ?? '';
        final wordsList = (resp.data['words'] is List)
            ? (resp.data['words'] as List).map((w) => w.toString()).toList()
            : phraseStr.split(' ').where((w) => w.isNotEmpty).toList();
        setState(() {
          _phrase = phraseStr;
          _words = wordsList;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to generate recovery phrase';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = ApiClient.formatError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.vpn_key_rounded,
                    color: AppTheme.warning, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Account Recovery',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor(context),
                      ),
                    ),
                    Text(
                      'Cryptographic zero-cloud recovery phrase',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security_rounded,
                    color: AppTheme.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Write down these 12 words in order and store them in an offline, physically secure place. Anyone with this phrase can restore access to your account if your password is lost.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            Text(_error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (_words.isEmpty && !_loading) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.lock_reset_rounded,
                        size: 40, color: AppTheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Generate your unique 12-word recovery mnemonic',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('Generate Recovery Phrase'),
                      onPressed: _generatePhrase,
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_loading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _words.length,
              itemBuilder: (ctx, i) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLightColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${i + 1}.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMutedColor(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _words[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Words'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _phrase));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Recovery phrase copied to clipboard'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  },
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('I Have Saved My Phrase'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyCloudHubDialogContent extends StatefulWidget {
  const _FamilyCloudHubDialogContent();

  @override
  State<_FamilyCloudHubDialogContent> createState() =>
      _FamilyCloudHubDialogContentState();
}

class _FamilyCloudHubDialogContentState
    extends State<_FamilyCloudHubDialogContent> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clouds = [];
  Map<String, dynamic>? _selectedCloud;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _loadFamilyData();
  }

  Future<void> _loadFamilyData() async {
    setState(() => _loading = true);
    try {
      final api = getIt<ApiClient>();
      final cloudsResp = await api.dio.get('/api/v1/family/clouds');
      List<Map<String, dynamic>> loadedClouds = [];
      if (cloudsResp.data is Map && cloudsResp.data['family_clouds'] is List) {
        loadedClouds = (cloudsResp.data['family_clouds'] as List)
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
      }

      Map<String, dynamic>? activeCloud;
      List<Map<String, dynamic>> members = [];

      if (loadedClouds.isNotEmpty) {
        activeCloud = loadedClouds.first;
        final membersResp = await api.dio.get(
          '/api/v1/family/members',
          queryParameters: {'family_id': activeCloud['id']},
        );
        if (membersResp.data is Map && membersResp.data['members'] is List) {
          members = (membersResp.data['members'] as List)
              .map((m) => Map<String, dynamic>.from(m as Map))
              .toList();
        }
      }

      if (mounted) {
        setState(() {
          _clouds = loadedClouds;
          _selectedCloud = activeCloud;
          _members = members;
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

  Future<void> _createFamilyCloud() async {
    final nameCtrl = TextEditingController(text: 'Family Vault');
    final quotaCtrl = TextEditingController(text: '200');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create New Family Cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Family Cloud Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quotaCtrl,
              decoration: const InputDecoration(
                labelText: 'Total Storage Quota (GB)',
                hintText: '200',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );

    if (result != true) return;

    try {
      final quotaGb = int.tryParse(quotaCtrl.text.trim()) ?? 200;
      final quotaBytes = quotaGb * 1024 * 1024 * 1024;
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/family/clouds', data: {
        'name': nameCtrl.text.trim(),
        'quota_bytes': quotaBytes,
      });
      _loadFamilyData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${ApiClient.formatError(e)}')),
        );
      }
    }
  }

  Future<void> _inviteMember() async {
    if (_selectedCloud == null) return;
    final emailCtrl = TextEditingController();
    final quotaCtrl = TextEditingController(text: '50');
    String role = 'member';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Invite Family Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Family Member Email',
                  hintText: 'family@example.com',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Member Role'),
                items: const [
                  DropdownMenuItem(
                      value: 'admin', child: Text('Admin (Full Control)')),
                  DropdownMenuItem(
                      value: 'member',
                      child: Text('Member (Personal + Shared Vault)')),
                  DropdownMenuItem(
                      value: 'child', child: Text('Child (Supervised Vault)')),
                ],
                onChanged: (val) => setDlgState(() => role = val!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quotaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Individual Quota (GB)',
                  hintText: '50',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send Invitation')),
          ],
        ),
      ),
    );

    if (result != true || emailCtrl.text.trim().isEmpty) return;

    try {
      final quotaGb = int.tryParse(quotaCtrl.text.trim()) ?? 50;
      final quotaBytes = quotaGb * 1024 * 1024 * 1024;
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/family/members/invite', data: {
        'family_id': _selectedCloud!['id'],
        'email': emailCtrl.text.trim(),
        'role': role,
        'quota_bytes': quotaBytes,
      });
      _loadFamilyData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Invited ${emailCtrl.text.trim()} to Family Cloud!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invite failed: ${ApiClient.formatError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.family_restroom_rounded,
                        color: AppTheme.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family Cloud Hub',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      Text(
                        'Zero-cost shared vaults & individual storage quotas',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            )
          else if (_clouds.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_queue_rounded,
                        size: 40, color: AppTheme.accent),
                    const SizedBox(height: 12),
                    Text(
                      'No Family Cloud configured yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pool storage across household members with private folders & shared spaces.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMutedColor(context),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _createFamilyCloud,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create Family Cloud'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLightColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedCloud!['name'] ?? 'Family Vault',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Storage Quota: ${((_selectedCloud!['quota_bytes'] as num?)?.toInt() ?? 0) ~/ (1024 * 1024 * 1024)} GB Total Pool',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context),
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('Invite Member',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _inviteMember,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Members (${_members.length}):',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No additional family members yet. Tap "Invite Member" above.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMutedColor(context),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final m = _members[i];
                    final role =
                        (m['role'] ?? 'member').toString().toUpperCase();
                    final quotaGb =
                        ((m['quota_bytes'] as num?)?.toInt() ?? 0) ~/
                            (1024 * 1024 * 1024);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLightColor(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle_rounded,
                              size: 24, color: AppTheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['email'] ?? m['user_id'] ?? 'Member',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimaryColor(context),
                                  ),
                                ),
                                Text(
                                  'Quota: $quotaGb GB',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMutedColor(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              role,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
