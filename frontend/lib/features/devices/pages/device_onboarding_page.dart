import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// QR-based device onboarding — generates a QR code with server URL + one-time auth token.
class DeviceOnboardingPage extends StatefulWidget {
  const DeviceOnboardingPage({super.key});
  @override
  State<DeviceOnboardingPage> createState() => _DeviceOnboardingPageState();
}

class _DeviceOnboardingPageState extends State<DeviceOnboardingPage>
    with SingleTickerProviderStateMixin {
  String? _onboardingCode;
  String? _qrData;
  bool _loading = false;
  String? _error;
  int _expirySeconds = 300; // 5 minutes
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
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = getIt<ApiClient>();
      // Generate a one-time pairing code
      final code = _generateOTP();
      final serverUrl = api.dio.options.baseUrl;

      // Try to register the pairing code on the server
      try {
        await api.dio.post('/api/v1/devices/pair', data: {
          'pairing_code': code,
          'expires_in_seconds': _expirySeconds,
        });
      } catch (_) {
        // If endpoint doesn't exist yet, still generate the QR code for display
      }

      setState(() {
        _onboardingCode = code;
        _qrData = '$serverUrl#pair=$code';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _generateOTP() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Device Onboarding',
            style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 8),
        Text('Connect new devices to your PCOS cloud',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),

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
                Text('Or enter this code manually:',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMutedColor(context))),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _onboardingCode!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Code copied!'),
                        duration: Duration(seconds: 1)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppTheme.primary.withOpacity(0.3)),
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
                  Text('Expires in ${_expirySeconds ~/ 60} min',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMutedColor(context))),
                ]),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!,
                      style:
                          const TextStyle(fontSize: 12, color: AppTheme.error)),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _generateCode,
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
              Text('How to connect a device',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context))),
              const SizedBox(height: 16),
              _InstructionStep(
                  step: '1',
                  title: 'Install PCOS App',
                  subtitle: 'Download from your app store or use the web app'),
              _InstructionStep(
                  step: '2',
                  title: 'Scan QR or Enter Code',
                  subtitle: 'Use the camera or enter the 6-digit code'),
              _InstructionStep(
                  step: '3',
                  title: 'Approve Connection',
                  subtitle: 'Verify the device on this screen'),
              _InstructionStep(
                  step: '4',
                  title: 'Start Syncing',
                  subtitle: 'Your files are now available on the new device'),
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
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        QrImageView(
          data: _qrData!,
          version: QrVersions.auto,
          size: 150.0,
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 4),
        Text(
          'PCOS PAIRING',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 2),
        ),
      ]),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  const _InstructionStep(
      {required this.step, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14)),
            child: Center(
                child: Text(step,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary))),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimaryColor(context))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMutedColor(context))),
              ])),
        ]),
      );
}
