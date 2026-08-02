import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// Responsive shell layout with sidebar (desktop), compact rail (tablet), and drawer (mobile).
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

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String path;
  const _NavItem(this.label, this.icon, this.activeIcon, this.path);
}

const _navItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded, '/dashboard'),
  _NavItem('Files', Icons.folder_outlined, Icons.folder_rounded, '/files'),
  _NavItem('Search', Icons.search_outlined, Icons.search_rounded, '/search'),
  _NavItem('Devices', Icons.devices_outlined, Icons.devices_rounded, '/devices'),
  _NavItem('Trash', Icons.delete_outline_rounded, Icons.delete_rounded, '/trash'),
  _NavItem('Settings', Icons.settings_outlined, Icons.settings_rounded, '/settings'),
];

int _currentIndex(BuildContext context) {
  final location = GoRouterState.of(context).matchedLocation;
  for (int i = 0; i < _navItems.length; i++) {
    if (location.startsWith(_navItems[i].path)) return i;
  }
  return 0;
}

// ─── Desktop (full sidebar) ─────────────────────────────
class _DesktopShell extends StatelessWidget {
  final Widget child;
  const _DesktopShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(children: [
        // Sidebar
        Container(
          width: 240,
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(right: BorderSide(color: AppTheme.border)),
          ),
          child: Column(children: [
            // Logo
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PCOS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: 1)),
                  Text('Personal Cloud OS', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                ]),
              ]),
            ),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 8),

            // Nav items
            ...List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final isActive = idx == i;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Material(
                  color: isActive ? AppTheme.primary.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => context.go(item.path),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(children: [
                        Icon(isActive ? item.activeIcon : item.icon, size: 20, color: isActive ? AppTheme.primary : AppTheme.textMuted),
                        const SizedBox(width: 12),
                        Text(item.label, style: TextStyle(fontSize: 14, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? AppTheme.primary : AppTheme.textSecondary)),
                      ]),
                    ),
                  ),
                ),
              );
            }),

            const Spacer(),
            // Storage indicator
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.cloud_done_rounded, size: 16, color: AppTheme.primary),
                  SizedBox(width: 6),
                  Text('Storage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: 0.0, minHeight: 6, backgroundColor: AppTheme.border, color: AppTheme.primary)),
                const SizedBox(height: 6),
                const Text('Unlimited', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ]),
            ),
            const SizedBox(height: 8),
          ]),
        ),
        // Content
        Expanded(child: child),
      ]),
    );
  }
}

// ─── Tablet (compact rail) ──────────────────────────────
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
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 20),
            ),
          ),
          destinations: _navItems.map((item) => NavigationRailDestination(
            icon: Icon(item.icon, color: AppTheme.textMuted),
            selectedIcon: Icon(item.activeIcon, color: AppTheme.primary),
            label: Text(item.label),
          )).toList(),
        ),
        const VerticalDivider(thickness: 1, width: 1, color: AppTheme.border),
        Expanded(child: child),
      ]),
    );
  }
}

// ─── Mobile (bottom nav + drawer) ──────────────────────
class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 8),
          const Text('PCOS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        ]),
      ),
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
        child: BottomNavigationBar(
          currentIndex: idx < 5 ? idx : 0,
          backgroundColor: AppTheme.surface,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textMuted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          onTap: (i) => context.go(_navItems[i].path),
          items: _navItems.map((item) => BottomNavigationBarItem(icon: Icon(item.icon), activeIcon: Icon(item.activeIcon), label: item.label)).toList(),
        ),
      ),
    );
  }
}
