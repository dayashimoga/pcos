import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final AuthBloc _authBloc;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _authBloc = getIt<AuthBloc>();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _authBloc.close();
    super.dispose();
  }

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      _authBloc.add(
        AuthLoginRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      bloc: _authBloc,
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          context.go('/dashboard');
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 40),
                        _buildFormCard(),
                        const SizedBox(height: 24),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.accent],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.cloud_rounded, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome to PCOS',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your personal cloud, unified & secure',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('login_email_field'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Email is required';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('login_password_field'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            BlocBuilder<AuthBloc, AuthState>(
              bloc: _authBloc,
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  child: ElevatedButton(
                    key: const Key('login_submit_button'),
                    onPressed: isLoading ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign In',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('OR',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.4))),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
            ]),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('pair_device_button'),
              onPressed: () => _showPairingDialog(context, initialTab: 0),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: BorderSide(color: AppTheme.primary.withOpacity(0.6)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_2_rounded,
                  color: AppTheme.primary, size: 20),
              label: const Text('Show QR Code to Pair',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: const Key('scan_camera_button'),
              onPressed: () => context.go('/connect'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: AppTheme.primary.withOpacity(0.16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded,
                  color: AppTheme.primary, size: 20),
              label: const Text('Scan QR with Camera / Enter PIN',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showServerConfig(BuildContext context) {
    _showPairingDialog(context, initialTab: 3);
  }

  void _showPairingDialog(BuildContext context, {int initialTab = 0}) {
    final api = getIt<ApiClient>();
    final ctrl = TextEditingController(text: api.currentServerUrl);
    final codeCtrl = TextEditingController();
    int currentTab = initialTab;
    bool testing = false;
    String? testResult;
    bool? testSuccess;
    bool pairing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final serverUrl = ctrl.text.trim().isNotEmpty
              ? ctrl.text.trim()
              : api.currentServerUrl;
          final qrPayload = '$serverUrl/#/connect';

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded,
                      color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pair Device & Connect',
                    style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  splashRadius: 18,
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Segmented Tabs
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor(context),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppTheme.borderColor(context)),
                      ),
                      child: Row(
                        children: [
                          _buildDialogTabItem(
                            context: context,
                            index: 0,
                            activeIndex: currentTab,
                            icon: Icons.qr_code_rounded,
                            label: 'Show QR',
                            onTap: () => setDialogState(() => currentTab = 0),
                          ),
                          _buildDialogTabItem(
                            context: context,
                            index: 1,
                            activeIndex: currentTab,
                            icon: Icons.camera_alt_rounded,
                            label: 'Scan QR',
                            onTap: () => setDialogState(() => currentTab = 1),
                          ),
                          _buildDialogTabItem(
                            context: context,
                            index: 2,
                            activeIndex: currentTab,
                            icon: Icons.pin_rounded,
                            label: 'PIN Code',
                            onTap: () => setDialogState(() => currentTab = 2),
                          ),
                          _buildDialogTabItem(
                            context: context,
                            index: 3,
                            activeIndex: currentTab,
                            icon: Icons.dns_rounded,
                            label: 'Server',
                            onTap: () => setDialogState(() => currentTab = 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tab 0: Show QR Code
                    if (currentTab == 0) ...[
                      Text(
                        'Point your phone camera or PCOS app at this QR code to connect instantly:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrPayload,
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF1E1E2E),
                          ),
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF11111B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor(context),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.link_rounded,
                                size: 14, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                qrPayload,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textPrimaryColor(context)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: qrPayload));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Pairing link copied to clipboard!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Icon(Icons.copy_rounded,
                                  size: 14, color: AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 14, color: AppTheme.success),
                          const SizedBox(width: 4),
                          Text(
                            'Works with iOS, Android Camera, Google Lens, or PCOS App',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMutedColor(context)),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline_rounded,
                                    size: 16, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'How Device Pairing Works',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimaryColor(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '1. Scanning this QR code automatically sets your mobile app to this server.\n'
                              '2. To generate an active 6-digit pairing code for your account, sign in on this computer and click "Pair Phone / Device" on your dashboard.\n'
                              '3. Or on your phone, tap "Back to Sign In" to log in directly with your email & password.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: AppTheme.textMutedColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Tab 1: Scan QR Code with Camera
                    if (currentTab == 1) ...[
                      Text(
                        'Scan a PCOS QR code displayed on your PC screen or terminal to pair this device:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded,
                            size: 48, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const Key('dialog_open_camera_scanner_button'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.go('/connect');
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('Open Camera Scanner',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Uses device camera with live barcode recognition.',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMutedColor(context)),
                      ),
                    ],

                    // Tab 2: 6-Digit Code
                    if (currentTab == 2) ...[
                      Text(
                        'Enter the 6-digit one-time code shown on your host screen:',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                        decoration: const InputDecoration(
                          hintText: '856408',
                          counterText: '',
                          prefixIcon: Icon(Icons.pin_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              final text = data?.text?.trim() ?? '';
                              if (text.isNotEmpty) {
                                if (text.contains('code=')) {
                                  final uri = Uri.tryParse(text);
                                  if (uri != null &&
                                      uri.queryParameters['code'] != null) {
                                    codeCtrl.text =
                                        uri.queryParameters['code']!;
                                  }
                                } else if (text.length == 6 &&
                                    int.tryParse(text) != null) {
                                  codeCtrl.text = text;
                                }
                                setDialogState(() {});
                              }
                            },
                            icon: const Icon(Icons.paste_rounded, size: 14),
                            label: const Text('Paste Code',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      if (testResult != null && testSuccess == false) ...[
                        const SizedBox(height: 10),
                        _buildStatusBadge(testResult!, false),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: pairing
                            ? null
                            : () async {
                                final code = codeCtrl.text.trim();
                                if (code.length != 6) {
                                  setDialogState(() {
                                    testResult =
                                        'Please enter a full 6-digit code';
                                    testSuccess = false;
                                  });
                                  return;
                                }
                                setDialogState(() {
                                  pairing = true;
                                  testResult = null;
                                });
                                try {
                                  await api.redeemPairingCode(code,
                                      serverUrl: serverUrl);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Device paired successfully! Welcome to PCOS.'),
                                        backgroundColor: AppTheme.success,
                                      ),
                                    );
                                    GoRouter.of(context).go('/dashboard');
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    pairing = false;
                                    testSuccess = false;
                                    testResult = ApiClient.formatError(e);
                                  });
                                }
                              },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: pairing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Connect & Sign In',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],

                    // Tab 3: Server URL
                    if (currentTab == 3) ...[
                      Text(
                        'Configure target PCOS server IP / domain (e.g. for self-hosted or LAN nodes):',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: ctrl,
                        style: TextStyle(
                            color: AppTheme.textPrimaryColor(context)),
                        decoration: const InputDecoration(
                          labelText: 'Server IP / URL',
                          hintText:
                              'https://pcos-control-plane... or http://192.168.1.50',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (testResult != null) ...[
                        _buildStatusBadge(testResult!, testSuccess ?? false),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: testing
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        testing = true;
                                        testResult = null;
                                      });
                                      final err = await api
                                          .testServerUrl(ctrl.text.trim());
                                      setDialogState(() {
                                        testing = false;
                                        testSuccess = (err == null);
                                        testResult =
                                            err ?? 'Connection successful!';
                                      });
                                    },
                              icon: testing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_find_rounded,
                                      size: 14),
                              label: Text(testing ? 'Testing...' : 'Test',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                final newUrl = ctrl.text.trim();
                                if (newUrl.isNotEmpty) {
                                  await api.setServerUrl(newUrl);
                                  if (mounted) setState(() {});
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Server connected: ${api.currentServerUrl}'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Save Server',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDialogTabItem({
    required BuildContext context,
    required int index,
    required int activeIndex,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isActive = index == activeIndex;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    isActive ? Colors.white : AppTheme.textMutedColor(context),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive
                      ? Colors.white
                      : AppTheme.textMutedColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, bool success) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (success ? AppTheme.success : AppTheme.error).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: success ? AppTheme.success : AppTheme.error),
      ),
      child: Row(children: [
        Icon(
          success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 16,
          color: success ? AppTheme.success : AppTheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: success ? AppTheme.success : AppTheme.error,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildFooter() {
    final api = getIt<ApiClient>();
    final serverUrl = api.currentServerUrl;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account?",
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
            TextButton(
              key: const Key('register_link'),
              onPressed: () => context.go('/register'),
              child: const Text(
                'Create One',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _showServerConfig(context),
          icon: const Icon(Icons.settings_ethernet_rounded,
              size: 16, color: AppTheme.textMuted),
          label: Text(
            'Server: $serverUrl',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }
}
