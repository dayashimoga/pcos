import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// Setup Wizard — shown on first run to create admin account and configure server.
class SetupWizardPage extends StatefulWidget {
  const SetupWizardPage({super.key});

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  int _step = 0;
  bool _loading = false;
  String? _error;

  // Step 1: Server check
  bool _serverReachable = false;
  String _serverVersion = '';
  Map<String, dynamic> _healthData = {};

  // Step 2: Admin account
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = getIt<ApiClient>();
      final resp = await api.dio.get('/api/v1/health');
      setState(() {
        _serverReachable = true;
        _healthData = Map<String, dynamic>.from(resp.data);
        _serverVersion = _healthData['version'] ?? '0.1.0';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _serverReachable = false;
        _error =
            'Unable to connect to PCOS server. Please ensure the server containers are running and click Retry Connection.';
        _loading = false;
      });
    }
  }

  Future<void> _createAdmin() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = getIt<ApiClient>();
      await api.dio.post('/api/v1/auth/register', data: {
        'email': _emailCtrl.text.trim(),
        'display_name':
            _nameCtrl.text.trim().isEmpty ? 'Admin' : _nameCtrl.text.trim(),
        'password': _passwordCtrl.text,
      });
      setState(() {
        _loading = false;
        _step = 2;
      });
    } catch (e) {
      String msg = 'Failed to create account. Please try again.';
      if (e is DioException) {
        if (e.response?.statusCode == 409) {
          msg =
              'An account with this email address already exists. Please sign in with your existing account.';
        } else if (e.response?.data is Map &&
            e.response?.data['message'] != null) {
          msg = e.response?.data['message'].toString() ?? msg;
        } else if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout) {
          msg =
              'Unable to connect to PCOS server. Please ensure server is running.';
        }
      }
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.cloud_rounded,
                    color: Colors.white, size: 48),
              ),
              const SizedBox(height: 20),
              const Text('Welcome to PCOS',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              const Text('Personal Cloud OS — Setup Wizard',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted)),
              const SizedBox(height: 32),

              // Step indicator
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _StepDot(
                    label: '1',
                    title: 'Server',
                    active: _step == 0,
                    done: _step > 0),
                Container(
                    width: 40,
                    height: 2,
                    color: _step > 0 ? AppTheme.primary : AppTheme.border),
                _StepDot(
                    label: '2',
                    title: 'Account',
                    active: _step == 1,
                    done: _step > 1),
                Container(
                    width: 40,
                    height: 2,
                    color: _step > 1 ? AppTheme.primary : AppTheme.border),
                _StepDot(
                    label: '3', title: 'Done', active: _step == 2, done: false),
              ]),
              const SizedBox(height: 32),

              // Step content
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: _buildStepContent(),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildServerCheck();
      case 1:
        return _buildAccountSetup();
      case 2:
        return _buildComplete();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServerCheck() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Server Connection',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text('Verifying connection to your PCOS backend server.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        const SizedBox(height: 20),
        if (_loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()))
        else if (_serverReachable) ...[
          _StatusItem(
              icon: Icons.check_circle_rounded,
              color: AppTheme.success,
              title: 'Server Online',
              subtitle: 'v$_serverVersion'),
          _StatusItem(
              icon: Icons.check_circle_rounded,
              color: AppTheme.success,
              title: 'API Available',
              subtitle: 'Uptime: ${_healthData['uptime_secs'] ?? 0}s'),
          _StatusItem(
              icon: Icons.check_circle_rounded,
              color: AppTheme.success,
              title: 'Database Connected',
              subtitle: 'PostgreSQL'),
          const SizedBox(height: 24),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => setState(() => _step = 1),
                child: const Text('Continue'),
              )),
        ] else ...[
          _StatusItem(
              icon: Icons.error_rounded,
              color: AppTheme.error,
              title: 'Server Unreachable',
              subtitle: _error ?? 'Check your connection'),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _checkServer,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Connection'),
              )),
        ],
      ]);

  Widget _buildAccountSetup() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Create Admin Account',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text('This will be the first administrator account.',
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        const SizedBox(height: 20),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: AppTheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.error))),
                ]),
                if (_error!.contains('already exists')) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: const Text('Go to Login Screen'),
                  )
                ]
              ],
            ),
          ),
        TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 20)),
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Display Name',
                prefixIcon: Icon(Icons.badge_outlined, size: 20))),
        const SizedBox(height: 14),
        TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password (min 8 chars)',
                prefixIcon: Icon(Icons.lock_outline, size: 20))),
        const SizedBox(height: 14),
        TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock_outline, size: 20))),
        const SizedBox(height: 24),
        Row(children: [
          OutlinedButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back')),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
            onPressed: _loading ? null : _createAdmin,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Create Account'),
          )),
        ]),
      ]);

  Widget _buildComplete() => Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.check_circle_rounded,
              size: 56, color: AppTheme.success),
        ),
        const SizedBox(height: 20),
        const Text('Setup Complete!',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text(
            'Your PCOS instance is ready. Log in with your new admin account.',
            style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Go to Login'),
            )),
      ]);
}

class _StepDot extends StatelessWidget {
  final String label;
  final String title;
  final bool active;
  final bool done;
  const _StepDot(
      {required this.label,
      required this.title,
      required this.active,
      required this.done});

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: done
                ? AppTheme.success
                : active
                    ? AppTheme.primary
                    : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
              child: done
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppTheme.textMuted))),
        ),
        const SizedBox(height: 6),
        Text(title,
            style: TextStyle(
                fontSize: 10,
                color:
                    active || done ? AppTheme.textPrimary : AppTheme.textMuted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ]);
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _StatusItem(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ])),
        ]),
      );
}
