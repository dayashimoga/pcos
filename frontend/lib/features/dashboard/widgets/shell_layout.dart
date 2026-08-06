import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

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
    ('Dashboard', Icons.dashboard_rounded, '/dashboard'),
    ('Files', Icons.folder_rounded, '/files'),
    ('Search', Icons.search_rounded, '/search'),
    ('Devices', Icons.devices_rounded, '/devices'),
    ('Trash', Icons.delete_rounded, '/trash'),
    ('Admin', Icons.admin_panel_settings_rounded, '/admin'),
    ('API Explorer', Icons.api_rounded, '/admin/api'),
    ('Duplicates', Icons.find_replace_rounded, '/duplicates'),
    ('Settings', Icons.settings_rounded, '/settings'),
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
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
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
                decoration: const InputDecoration(
                  hintText: 'Search pages, actions...',
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppTheme.textMuted, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                style:
                    const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                children: _filtered
                    .map((p) => ListTile(
                          leading:
                              Icon(p.$2, size: 20, color: AppTheme.primary),
                          title: Text(p.$1,
                              style: const TextStyle(
                                  fontSize: 14, color: AppTheme.textPrimary)),
                          trailing: Text('Go',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted.withOpacity(0.6))),
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          hoverColor: AppTheme.primary.withOpacity(0.08),
                          onTap: () {
                            Navigator.pop(context);
                            context.go(p.$3);
                          },
                        ))
                    .toList(),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border))),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('ESC',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                const Text('to close',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('Ctrl+K',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
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
  _NavItem('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded,
      '/dashboard'),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded, '/files'),
  _NavItem('Gallery', Icons.photo_library_outlined, Icons.photo_library_rounded,
      '/gallery'),
  _NavItem('Search', Icons.search_outlined, Icons.search_rounded, '/search'),
  _NavItem(
      'Devices', Icons.devices_outlined, Icons.devices_rounded, '/devices'),
  _NavItem(
      'Trash', Icons.delete_outline_rounded, Icons.delete_rounded, '/trash'),
  _NavItem('Duplicates', Icons.find_replace_outlined,
      Icons.find_replace_rounded, '/duplicates'),
  _NavItem('Admin', Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings_rounded, '/admin'),
  _NavItem('API Explorer', Icons.api_outlined, Icons.api_rounded, '/admin/api'),
  _NavItem('Doctor', Icons.health_and_safety_outlined,
      Icons.health_and_safety_rounded, '/doctor'),
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
                              child: Text('⌘K',
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

                // Storage indicator
                if (!_collapsed)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: boxBg, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.cloud_done_rounded,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Text('Storage',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary)),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                                value: 0.0,
                                minHeight: 6,
                                backgroundColor: borderColor,
                                color: AppTheme.primary),
                          ),
                          const SizedBox(height: 6),
                          Text('Unlimited',
                              style: TextStyle(fontSize: 11, color: textMuted)),
                        ]),
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
      backgroundColor: AppTheme.background,
      body: Row(children: [
        NavigationRail(
          selectedIndex: idx,
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          onDestinationSelected: (i) => context.go(_navItems[i].path),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.cloud_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          destinations: _navItems
              .map((item) => NavigationRailDestination(
                    icon: Tooltip(
                        message: item.label,
                        child: Icon(item.icon, color: AppTheme.textMuted)),
                    selectedIcon:
                        Icon(item.activeIcon, color: AppTheme.primary),
                    label:
                        Text(item.label, style: const TextStyle(fontSize: 10)),
                  ))
              .toList(),
        ),
        const VerticalDivider(thickness: 1, width: 1, color: AppTheme.border),
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
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
          const Text('PCOS',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded,
                size: 22, color: AppTheme.textMuted),
            onPressed: () => _showQuickSearch(context),
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined,
                size: 22, color: AppTheme.textMuted),
            onPressed: () => context.go('/admin'),
            tooltip: 'Admin',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                size: 22, color: AppTheme.textMuted),
            onPressed: () => context.go('/settings'),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border))),
        child: NavigationBar(
          selectedIndex: mobileIdx,
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          onDestinationSelected: (i) => context.go(_navItems[i].path),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          destinations: List.generate(
              _mobileNavItems,
              (i) => NavigationDestination(
                    icon: Icon(_navItems[i].icon,
                        color: AppTheme.textMuted, size: 22),
                    selectedIcon: Icon(_navItems[i].activeIcon,
                        color: AppTheme.primary, size: 22),
                    label: _navItems[i].label,
                  )),
        ),
      ),
    );
  }
}
