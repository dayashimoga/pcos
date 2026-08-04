import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/admin/pages/admin_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/dashboard/widgets/shell_layout.dart';
import '../../features/devices/pages/devices_page.dart';
import '../../features/doctor/pages/doctor_page.dart';
import '../../features/files/pages/files_page.dart';
import '../../features/search/pages/search_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/setup/pages/setup_wizard_page.dart';
import '../../features/trash/pages/trash_page.dart';

/// Application router with authentication guard.
class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  /// Check if user is authenticated (has token in storage).
  static bool _isAuthenticated() {
    // Token check via shared state — in production, use secure storage
    return _authToken != null && _authToken!.isNotEmpty;
  }

  static String? _authToken;
  static void setAuthToken(String? token) => _authToken = token;

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuth = _isAuthenticated();
      final isAuthPage = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (!isAuth && !isAuthPage) return '/login';
      if (isAuth && isAuthPage) return '/dashboard';
      return null;
    },
    routes: [
      // Auth routes (no shell)
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupWizardPage()),

      // Shell routes (with sidebar/drawer)
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => ShellLayout(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
          GoRoute(path: '/files', builder: (_, __) => const FilesPage()),
          GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
          GoRoute(path: '/devices', builder: (_, __) => const DevicesPage()),
          GoRoute(path: '/trash', builder: (_, __) => const TrashPage()),
          GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
          GoRoute(path: '/doctor', builder: (_, __) => const DoctorPage()),
        ],
      ),
    ],
  );
}
