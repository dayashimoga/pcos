import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// QR-based device onboarding — generates a real QR code with server URL + one-time auth token.
class DeviceOnboardingPage extends StatefulWidget {
  const DeviceOnboardingPage({super.key});
  @override
  State<DeviceOnboardingPage> createState() => _DeviceOnboardingPageState();
}

class _DeviceOnboardingPageState extends State<DeviceOnboardingPage>
    with SingleTickerProviderStateMixin {
  String? _onboardingCode;
  String? _enrollmentToken;
  String? _qrData;
  bool _loading = false;
  String? _error;
  bool _isAuthError = false;
  int _expirySeconds = 300;
  String? _connectedDeviceName;
  Map<String, dynamic>? _candidateDevice;
  bool _approving = false;
  Timer? _pollTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _generateCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startPollingForPairingStatus() {
    _pollTimer?.cancel();
    if (_onboardingCode == null) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final api = getIt<ApiClient>();
        final statusRes = await api.getPairingStatus(
          code: _onboardingCode,
          token: _enrollmentToken,
        );

        final status = statusRes['status'] as String?;
        final candidate =
            statusRes['candidate_device'] as Map<String, dynamic>?;

        if (status == 'pending_approval' && candidate != null) {
          if (mounted) {
            setState(() {
              _candidateDevice = candidate;
            });
          }
        } else if (status == 'approved') {
          _pollTimer?.cancel();
          if (mounted) {
            setState(() {
              _candidateDevice = null;
              _connectedDeviceName =
                  candidate?['device_name']?.toString() ?? 'New Device';
            });
          }
        } else if (status == 'expired' || status == 'rejected') {
          _pollTimer?.cancel();
        }
      } catch (_) {}
    });
  }

  Future<void> _handleApproveConnection(bool approve) async {
    if (_onboardingCode == null) return;
    setState(() => _approving = true);
    final api = getIt<ApiClient>();
    try {
      await api.approvePairing(
        code: _onboardingCode,
        token: _enrollmentToken,
        approved: approve,
      );
      if (!mounted) return;
      if (approve) {
        setState(() {
          _approving = false;
          _connectedDeviceName =
              _candidateDevice?['device_name']?.toString() ?? 'New Device';
          _candidateDevice = null;
        });
      } else {
        setState(() {
          _approving = false;
          _candidateDevice = null;
        });
        _generateCode();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _approving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Failed to process approval: ${ApiClient.formatError(e)}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _generateCode() async {
    setState(() {
      _loading = true;
      _error = null;
      _isAuthError = false;
      _connectedDeviceName = null;
      _candidateDevice = null;
    });

    final api = getIt<ApiClient>();
    String targetBaseUrl = api.currentServerUrl;

    try {
      final res = await api.dio.post('/api/v1/devices/pair', data: {
        'expires_in_seconds': 300,
      });

      if (res.data != null && res.data['pairing_code'] != null) {
        final code = res.data['pairing_code'] as String;
        final token = res.data['enrollment_token'] as String?;
        final qrPayload = res.data['qr_payload'] as String? ??
            '$targetBaseUrl/#/pair?code=$code&token=${token ?? ""}';
        setState(() {
          _onboardingCode = code;
          _enrollmentToken = token;
          _qrData = qrPayload;
          _expirySeconds =
              (res.data['expires_in_seconds'] as num?)?.toInt() ?? 300;
          _loading = false;
        });
        _startPollingForPairingStatus();
      } else {
        throw Exception('Invalid pairing response');
      }
    } catch (e) {
      final errStr = ApiClient.formatError(e);
      final isAuth =
          errStr.contains('Session expired') || errStr.contains('sign in');
      setState(() {
        _loading = false;
        _isAuthError = isAuth;
        _error = isAuth
            ? 'You must be signed in to your PCOS account to pair a new device.'
            : 'Unable to reach PCOS pairing server: $errStr';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Device Onboarding',
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        Text('Connect new devices to your PCOS personal cloud',
            style: Theme.of(context).textTheme.bodyLarge),
        // Pending Approval State
        if (_candidateDevice != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: AppTheme.surfaceColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppTheme.primary, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_android_rounded,
                            size: 40, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Device Wants to Connect',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_candidateDevice!['device_name']} is requesting to pair with your PCOS account using code $_onboardingCode.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text('OS',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppTheme.textMutedColor(context))),
                                const SizedBox(height: 2),
                                Text(
                                  '${_candidateDevice!['os']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text('Type',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            AppTheme.textMutedColor(context))),
                                const SizedBox(height: 2),
                                Text(
                                  '${_candidateDevice!['device_type']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_approving)
                        const CircularProgressIndicator()
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _handleApproveConnection(false),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary),
                                onPressed: () => _handleApproveConnection(true),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Approve Connection'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (_connectedDeviceName != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: AppTheme.surfaceColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppTheme.success, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded,
                            size: 40, color: AppTheme.success),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Device Connected!',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_connectedDeviceName has successfully paired and authenticated with your cloud.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textMutedColor(context)),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.go('/devices'),
                        icon: const Icon(Icons.devices_rounded),
                        label: const Text('View All Connected Devices'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          // Main card
          Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Column(children: [
                // QR Code area
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary
                              .withOpacity(0.1 + _pulseController.value * 0.1),
                          blurRadius: 20 + _pulseController.value * 10,
                          spreadRadius: _pulseController.value * 4,
                        )
                      ],
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _buildQrPlaceholder(),
                  ),
                ),
                const SizedBox(height: 24),

                // Pairing code
                if (_onboardingCode != null) ...[
                  Text('Or enter this 6-digit code on your phone:',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMutedColor(context))),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _onboardingCode!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Pairing code copied!'),
                          duration: Duration(seconds: 1)));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundColor(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _onboardingCode!.split('').join(' '),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                              letterSpacing: 4,
                              fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.copy_rounded,
                            size: 18, color: AppTheme.textMutedColor(context)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: AppTheme.textMutedColor(context)),
                    const SizedBox(width: 4),
                    Text('Valid for ${_expirySeconds ~/ 60} minutes',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMutedColor(context))),
                  ]),
                  const SizedBox(height: 12),
                  if (_qrData != null)
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _qrData!));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Direct pairing link copied!')));
                      },
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy Direct Pairing Link'),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal_rounded,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'PC / Laptop / Server Onboarding:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryColor(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  'pcos-agent enroll ${_onboardingCode!} --start',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                tooltip: 'Copy 1-Command Onboarding',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text:
                                          'pcos-agent enroll ${_onboardingCode!} --start'));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Copied 1-command onboarding script!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.error)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppTheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.error)),
                            ),
                          ],
                        ),
                        if (_isAuthError) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: () => context.go('/login'),
                              child: const Text('Sign In Now'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _generateCode,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Generate New Code'),
                    )),
              ]),
            ),
          )),

        const SizedBox(height: 32),

        // Instructions
        Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor(context))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How to connect your device',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 16),
              const _InstructionStep(
                  step: '1',
                  title: 'Open Phone Camera',
                  subtitle:
                      'Simply point your phone\'s standard Camera or Google Lens at the QR code.'),
              const _InstructionStep(
                  step: '2',
                  title: 'Instant 1-Tap Connect',
                  subtitle:
                      'Tap the notification on your phone — it authenticates and opens your cloud instantly!'),
              const _InstructionStep(
                  step: '3',
                  title: 'Or Enter 6-Digit Code in App',
                  subtitle:
                      'In the PCOS Mobile App, tap "Pair Device" and enter the 6-digit number above.'),
              const _InstructionStep(
                  step: '4',
                  title: 'Zero Password Typing',
                  subtitle:
                      'Your device is enrolled securely with private tokens — no passwords needed.'),
            ]),
          ),
        )),
      ]),
    );
  }

  Widget _buildQrPlaceholder() {
    if (_qrData == null) {
      return const Center(
          child: Icon(Icons.qr_code_rounded, size: 80, color: Colors.black12));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: QrImageView(
        data: _qrData!,
        version: QrVersions.auto,
        size: 200,
        backgroundColor: Colors.white,
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF1E1E2E),
        ),
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF6C5CE7),
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;

  const _InstructionStep({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMutedColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
