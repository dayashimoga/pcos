import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/pages/files_page.dart' show formatFileSize;
import '../../transfers/widgets/transfer_center_dialog.dart';
import '../../transfers/widgets/transfer_status_indicator.dart';

/// Responsive shell layout: full sidebar (desktop ≥1100), compact rail (tablet ≥700), bottom nav (mobile).
class ShellLayout extends StatelessWidget {
  final Widget child;
  const ShellLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1100) return _DesktopShell(child: child);
    if (width >= 700) return _TabletShell(child: child);
    return _MobileShell(child: child);
  }
}

void _showQuickSearch(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const _QuickSearchOverlay(),
  );
}

class _QuickSearchOverlay extends StatefulWidget {
  const _QuickSearchOverlay();
  @override
  State<_QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<_QuickSearchOverlay> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  static const _pages = [
    ('Home', Icons.home_rounded, '/dashboard'),
    ('Files', Icons.folder_rounded, '/files'),
    ('Photos', Icons.photo_library_rounded, '/gallery'),
    ('Media Center', Icons.play_circle_fill_rounded, '/media'),
    ('Shared & Public Links', Icons.share_rounded, '/shared'),
    ('Storage Pools & Disks', Icons.storage_rounded, '/storage'),
    ('Devices & Pairing', Icons.devices_rounded, '/devices'),
    ('Search', Icons.search_rounded, '/search'),
    ('Trash', Icons.delete_rounded, '/trash'),
    ('Duplicates', Icons.find_replace_rounded, '/duplicates'),
    ('Transfer Center', Icons.swap_vert_rounded, '__transfers__'),
    ('Settings', Icons.settings_rounded, '/settings'),
    ('Doctor Diagnostics', Icons.health_and_safety_rounded, '/doctor'),
    ('Admin', Icons.admin_panel_settings_rounded, '/admin'),
    ('API Explorer', Icons.api_rounded, '/admin/api'),
  ];

  List<(String, IconData, String)> get _filtered {
    final q = _ctrl.text.toLowerCase();
    if (q.isEmpty) return _pages;
    return _pages.where((p) => p.$1.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor(context)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search pages, actions...',
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppTheme.textMutedColor(context), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                style: TextStyle(
                    fontSize: 15, color: AppTheme.textPrimaryColor(context)),
              ),
            ),
            Divider(color: AppTheme.borderColor(context), height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                children: _filtered
                    .map((p) => ListTile(
                          leading:
                              Icon(p.$2, size: 20, color: AppTheme.primary),
                          title: Text(p.$1,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textPrimaryColor(context))),
                          trailing: Text('Go',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMutedColor(context)
                                      .withOpacity(0.6))),
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          hoverColor: AppTheme.primary.withOpacity(0.08),
                          onTap: () {
                            Navigator.pop(context);
                            if (p.$3 == '__transfers__') {
                              TransferCenterDialog.show(context);
                            } else {
                              context.go(p.$3);
                            }
                          },
                        ))
                    .toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppTheme.borderColor(context)))),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceLightColor(context),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('ESC',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMutedColor(context),
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Text('to close',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMutedColor(context))),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceLightColor(context),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('Ctrl+K',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMutedColor(context),
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  const _NavItem(this.label, this.icon, this.activeIcon, this.path);
}

const _navItems = [
  _NavItem('Home', Icons.home_outlined, Icons.home_rounded, '/dashboard'),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded, '/files'),
  _NavItem('Photos', Icons.photo_library_outlined, Icons.photo_library_rounded,
      '/gallery'),
  _NavItem('Media', Icons.play_circle_outline_rounded,
      Icons.play_circle_fill_rounded, '/media'),
  _NavItem('Shared', Icons.share_outlined, Icons.share_rounded, '/shared'),
  _NavItem(
      'Devices', Icons.devices_outlined, Icons.devices_rounded, '/devices'),
  _NavItem(
      'Storage', Icons.storage_outlined, Icons.storage_rounded, '/storage'),
  _NavItem(
      'Settings', Icons.settings_outlined, Icons.settings_rounded, '/settings'),
];

// Mobile only shows first 5 items in bottom nav
const _mobileNavItems = 5;

int _currentIndex(BuildContext context) {
  final location = GoRouterState.of(context).matchedLocation;
  for (int i = 0; i < _navItems.length; i++) {
    if (location.startsWith(_navItems[i].path)) return i;
  }
  return 0;
}

// ─── Desktop (full sidebar) ─────────────────────────────
class _DesktopShell extends StatefulWidget {
  final Widget child;
  const _DesktopShell({required this.child});
  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    final sidebarWidth = _collapsed ? 72.0 : 240.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.textPrimary : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? AppTheme.textSecondary : const Color(0xFF475569);
    final textMuted = isDark ? AppTheme.textMuted : const Color(0xFF64748B);
    final boxBg = isDark ? AppTheme.background : const Color(0xFFF1F5F9);
    final borderColor = isDark ? AppTheme.border : const Color(0xFFE2E8F0);

    return CallbackShortcuts(
      bindings: {
        for (int i = 0; i < _navItems.length; i++)
          SingleActivator(
              LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
              control: true): () => context.go(_navItems[i].path),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _showQuickSearch(context),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            TransferCenterDialog.show(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Row(children: [
            // Sidebar
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: sidebarWidth,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(right: BorderSide(color: borderColor)),
              ),
              child: Column(children: [
                // Logo + collapse toggle
                Container(
                  padding: EdgeInsets.all(_collapsed ? 12 : 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cloud_rounded,
                          color: Colors.white, size: 22),
                    ),
                    if (!_collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PCOS',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimary,
                                      letterSpacing: 1)),
                              Text('Personal Cloud OS',
                                  style: TextStyle(
                                      fontSize: 10, color: textMuted)),
                            ]),
                      ),
                    ],
                  ]),
                ),
                Divider(color: borderColor, height: 1),
                // Search bar hint
                if (!_collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showQuickSearch(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: boxBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(children: [
                            Icon(Icons.search_rounded,
                                size: 16, color: textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text('Search...',
                                    style: TextStyle(
                                        fontSize: 13, color: textMuted))),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text('⌘K',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: IconButton(
                      onPressed: () => _showQuickSearch(context),
                      icon: Icon(Icons.search_rounded,
                          size: 20, color: textMuted),
                      tooltip: 'Search (Ctrl+K)',
                    ),
                  ),
                const SizedBox(height: 4),

                // Nav items
                ...List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final isActive = idx == i;
                  return Tooltip(
                    message: _collapsed ? item.label : '',
                    waitDuration: const Duration(milliseconds: 400),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: _collapsed ? 8 : 12, vertical: 2),
                      child: Material(
                        color: isActive
                            ? AppTheme.primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () => context.go(item.path),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: _collapsed ? 0 : 14, vertical: 11),
                            child: Row(
                              mainAxisAlignment: _collapsed
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                Icon(isActive ? item.activeIcon : item.icon,
                                    size: 20,
                                    color: isActive
                                        ? AppTheme.primary
                                        : textMuted),
                                if (!_collapsed) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(item.label,
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isActive
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: isActive
                                                ? AppTheme.primary
                                                : textSecondary),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (isActive)
                                    Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: AppTheme.primary,
                                            borderRadius:
                                                BorderRadius.circular(2))),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const Spacer(),

                // Collapse toggle
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => setState(() => _collapsed = !_collapsed),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Row(
                          mainAxisAlignment: _collapsed
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            Icon(
                                _collapsed
                                    ? Icons.chevron_right_rounded
                                    : Icons.chevron_left_rounded,
                                size: 20,
                                color: textMuted),
                            if (!_collapsed) ...[
                              const SizedBox(width: 12),
                              Text('Collapse',
                                  style: TextStyle(
                                      fontSize: 13, color: textMuted)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Transfer Status indicator
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: _collapsed ? 8 : 16, vertical: 4),
                  child: TransferStatusIndicator(compact: _collapsed),
                ),

                // Dynamic Real Storage indicator
                _SidebarStorageIndicator(
                  collapsed: _collapsed,
                  boxBg: boxBg,
                  borderColor: borderColor,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                ),
                const SizedBox(height: 8),
              ]),
            ),
            // Content
            Expanded(child: widget.child),
          ]),
        ),
      ),
    );
  }
}

// ─── Tablet (compact rail with tooltips) ─────────────────
class _TabletShell extends StatelessWidget {
  final Widget child;
  const _TabletShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      body: Row(children: [
        NavigationRail(
          selectedIndex: idx,
          backgroundColor: AppTheme.surfaceColor(context),
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          onDestinationSelected: (i) => context.go(_navItems[i].path),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.cloud_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(height: 8),
                const TransferStatusIndicator(compact: true),
              ],
            ),
          ),
          destinations: _navItems
              .map((item) => NavigationRailDestination(
                    icon: Tooltip(
                        message: item.label,
                        child: Icon(item.icon,
                            color: AppTheme.textMutedColor(context))),
                    selectedIcon:
                        Icon(item.activeIcon, color: AppTheme.primary),
                    label:
                        Text(item.label, style: const TextStyle(fontSize: 10)),
                  ))
              .toList(),
        ),
        VerticalDivider(
            thickness: 1, width: 1, color: AppTheme.borderColor(context)),
        Expanded(child: child),
      ]),
    );
  }
}

// ─── Mobile (bottom nav, only 5 items) ───────────────────
class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    final mobileIdx = idx < _mobileNavItems ? idx : 0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8)),
            child:
                const Icon(Icons.cloud_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Text('PCOS',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimaryColor(context))),
        ]),
        actions: [
          const TransferStatusIndicator(compact: true),
          IconButton(
            icon: Icon(Icons.search_rounded,
                size: 22, color: AppTheme.textMutedColor(context)),
            onPressed: () => _showQuickSearch(context),
            tooltip: 'Search',
          ),
          IconButton(
            icon: Icon(Icons.admin_panel_settings_outlined,
                size: 22, color: AppTheme.textMutedColor(context)),
            onPressed: () => context.go('/admin'),
            tooltip: 'Admin',
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                size: 22, color: AppTheme.textMutedColor(context)),
            onPressed: () => context.go('/settings'),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            border:
                Border(top: BorderSide(color: AppTheme.borderColor(context)))),
        child: NavigationBar(
          selectedIndex: mobileIdx,
          backgroundColor: AppTheme.surfaceColor(context),
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          onDestinationSelected: (i) => context.go(_navItems[i].path),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          destinations: List.generate(
              _mobileNavItems,
              (i) => NavigationDestination(
                    icon: Icon(_navItems[i].icon,
                        color: AppTheme.textMutedColor(context), size: 22),
                    selectedIcon: Icon(_navItems[i].activeIcon,
                        color: AppTheme.primary, size: 22),
                    label: _navItems[i].label,
                  )),
        ),
      ),
    );
  }
}

class _SidebarStorageIndicator extends StatefulWidget {
  final bool collapsed;
  final Color boxBg;
  final Color borderColor;
  final Color textPrimary;
  final Color textMuted;

  const _SidebarStorageIndicator({
    required this.collapsed,
    required this.boxBg,
    required this.borderColor,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  State<_SidebarStorageIndicator> createState() =>
      _SidebarStorageIndicatorState();
}

class _SidebarStorageIndicatorState extends State<_SidebarStorageIndicator> {
  int _totalBytes = 53687091200; // 50GB default
  int _availBytes = 53687091200;
  int _usedBytes = 0;

  @override
  void initState() {
    super.initState();
    _fetchUsage();
  }

  Future<void> _fetchUsage() async {
    try {
      final api = getIt<ApiClient>();
      final nodesResp = await api.dio.get('/api/v1/storage/nodes');
      final List rawNodes =
          nodesResp.data is Map && nodesResp.data['storage_nodes'] is List
              ? nodesResp.data['storage_nodes']
              : (nodesResp.data is List ? nodesResp.data : []);

      int total = 0;
      int avail = 0;
      for (final n in rawNodes) {
        total += ((n as Map)['total_capacity_bytes'] as num?)?.toInt() ?? 0;
        avail += (n['available_capacity_bytes'] as num?)?.toInt() ?? 0;
      }

      if (total == 0) {
        final userResp = await api.dio.get('/api/v1/users/me');
        if (userResp.data is Map) {
          total =
              (userResp.data['quota_bytes'] as num?)?.toInt() ?? 53687091200;
          final used = (userResp.data['used_bytes'] as num?)?.toInt() ?? 0;
          avail = total > used ? total - used : 0;
        }
      }

      if (mounted) {
        setState(() {
          _totalBytes = total;
          _availBytes = avail;
          _usedBytes = total > avail ? total - avail : 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: IconButton(
          icon: const Icon(Icons.cloud_done_rounded,
              size: 20, color: AppTheme.primary),
          tooltip:
              'Storage: ${formatFileSize(_availBytes)} free of ${formatFileSize(_totalBytes)}',
          onPressed: () => context.go('/storage'),
        ),
      );
    }

    final pct =
        _totalBytes > 0 ? (_usedBytes / _totalBytes).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: () => context.go('/storage'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.boxBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.cloud_done_rounded,
                  size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text('Storage Pools',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.textPrimary)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppTheme.primary),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: widget.borderColor,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatFileSize(_availBytes)} free of ${formatFileSize(_totalBytes)}',
              style: TextStyle(fontSize: 11, color: widget.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
