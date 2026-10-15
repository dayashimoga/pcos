import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent Theme Service supporting Light, Dark, and System modes.
/// Saves and restores user preference across restarts via SharedPreferences.
class ThemeService {
  static const String _prefKey = 'pcos_theme_mode';
  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        themeNotifier.value = ThemeMode.light;
      } else if (saved == 'dark') {
        themeNotifier.value = ThemeMode.dark;
      } else if (saved == 'system') {
        themeNotifier.value = ThemeMode.system;
      } else {
        themeNotifier.value = ThemeMode.dark;
      }
    } catch (_) {
      themeNotifier.value = ThemeMode.dark;
    }
  }

  static Future<void> setMode(ThemeMode mode) async {
    themeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system');
      await prefs.setString(_prefKey, str);
    } catch (_) {}
  }

  static Future<void> toggle() async {
    final next = themeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setMode(next);
  }
}

/// Compact, elegant Theme Switch widget (Light / Dark / System)
class ThemeSwitchWidget extends StatelessWidget {
  final bool compact;
  const ThemeSwitchWidget({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeNotifier,
      builder: (context, currentMode, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
        final border =
            isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final activeBg = isDark ? const Color(0xFF334155) : Colors.white;
        final textPrimary =
            isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
        final textMuted =
            isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

        if (compact) {
          return IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: ThemeService.toggle,
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
              color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOption(
                context: context,
                label: 'Light',
                icon: Icons.light_mode_rounded,
                isSelected: currentMode == ThemeMode.light,
                activeBg: activeBg,
                textPrimary: textPrimary,
                textMuted: textMuted,
                onTap: () => ThemeService.setMode(ThemeMode.light),
              ),
              _buildOption(
                context: context,
                label: 'Dark',
                icon: Icons.dark_mode_rounded,
                isSelected: currentMode == ThemeMode.dark,
                activeBg: activeBg,
                textPrimary: textPrimary,
                textMuted: textMuted,
                onTap: () => ThemeService.setMode(ThemeMode.dark),
              ),
              _buildOption(
                context: context,
                label: 'System',
                icon: Icons.auto_mode_rounded,
                isSelected: currentMode == ThemeMode.system,
                activeBg: activeBg,
                textPrimary: textPrimary,
                textMuted: textMuted,
                onTap: () => ThemeService.setMode(ThemeMode.system),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color activeBg,
    required Color textPrimary,
    required Color textMuted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? textPrimary : textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? textPrimary : textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
