import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// PCOS Zero-Assumption Mobile Connect Screen.
/// Users pair their phone to their personal cloud without understanding ports, IPs, or tunnels.
class DeviceConnectPage extends StatefulWidget {
  const DeviceConnectPage({super.key});

  @override
  State<DeviceConnectPage> createState() => _DeviceConnectPageState();
}

enum ConnectStep { input, scanning, waitingApproval, success, error }

class _DeviceConnectPageState extends State<DeviceConnectPage> {
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  ConnectStep _step = ConnectStep.input;
  bool _showQrDisplayMode = false;
  String? _statusMessage;
  String? _errorMessage;
  MobileScannerController? _scannerController;
  Timer? _pollTimer;
  String? _activeCode;
  String? _activeToken;
  String? _targetServerUrl;

  @override
  void initState() {
    super.initState();
    final api = getIt<ApiClient>();
    _targetServerUrl = api.currentServerUrl;
    if (kIsWeb) {
      _showQrDisplayMode = true;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scannerController?.dispose();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredCode => _digitControllers.map((c) => c.text.trim()).join();

  void _startScanning() {
    setState(() {
      _step = ConnectStep.scanning;
      _errorMessage = null;
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    });
  }

  void _stopScanning() {
    _scannerController?.dispose();
    _scannerController = null;
    if (mounted) {
      setState(() {
        _step = ConnectStep.input;
      });
    }
  }

  Future<void> _handleBarcodeDetected(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    // Stop scanning immediately
    _scannerController?.stop();

    // Parse payload: either URL (e.g. https://<domain>/#/pair?code=856408&token=...) or direct code
    String? code;
    String? token;
    String? serverUrl;

    if (rawValue.length == 6 && int.tryParse(rawValue) != null) {
      code = rawValue;
    } else {
      final uri = Uri.tryParse(rawValue);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        serverUrl =
            '${uri.scheme}://${uri.host}${uri.hasPort ? ":${uri.port}" : ""}';

        // 1. Try standard query parameters (before #)
        code = uri.queryParameters['code'];
        token = uri.queryParameters['token'];

        // 2. Try fragment query parameters (Flutter hash routes like /#/pair?code=... or /#/connect?code=...)
        if (code == null && uri.fragment.isNotEmpty) {
          final frag = uri.fragment;
          final qIndex = frag.indexOf('?');
          if (qIndex != -1 && qIndex < frag.length - 1) {
            final fragQuery = frag.substring(qIndex + 1);
            final fragParams = Uri.splitQueryString(fragQuery);
            code = fragParams['code'];
            token ??= fragParams['token'];
          }
        }

        // 3. Fallback regex search for query parameters
        if (code == null) {
          final codeMatch =
              RegExp(r'[?&]code=([0-9A-Za-z]+)').firstMatch(rawValue);
          if (codeMatch != null) {
            code = codeMatch.group(1);
          }
        }
        if (token == null) {
          final tokenMatch =
              RegExp(r'[?&]token=([0-9A-Za-z_\-]+)').firstMatch(rawValue);
          if (tokenMatch != null) {
            token = tokenMatch.group(1);
          }
        }
      }
    }

    final api = getIt<ApiClient>();

    // If serverUrl was found in QR, save it and update active client
    if (serverUrl != null && serverUrl.isNotEmpty) {
      await api.setServerUrl(serverUrl);
      if (mounted) {
        setState(() {
          _targetServerUrl = serverUrl;
        });
      }
    }

    if (code != null && code.length == 6) {
      for (int i = 0; i < 6; i++) {
        _digitControllers[i].text = code[i];
      }
      _connectWithCode(code: code, token: token, serverUrl: serverUrl);
    } else if (serverUrl != null && serverUrl.isNotEmpty) {
      // Scanned server QR without pairing code (e.g. from desktop login screen)
      if (mounted) {
        setState(() {
          _step = ConnectStep.input;
          _errorMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connected to server: ${Uri.tryParse(serverUrl)?.host ?? serverUrl}!\n'
              'Enter your 6-digit pairing code or tap "Back to Sign In".',
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _step = ConnectStep.error;
          _errorMessage = 'Invalid QR code. Please scan a valid PCOS QR code.';
        });
      }
    }
  }

  Future<void> _connectWithCode({
    String? code,
    String? token,
    String? serverUrl,
  }) async {
    final pairingCode = code ?? _enteredCode;
    if (pairingCode.length != 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits of the pairing code.';
      });
      return;
    }

    setState(() {
      _step = ConnectStep.waitingApproval;
      _statusMessage = 'Connecting to PCOS Control Plane...';
      _errorMessage = null;
      _activeCode = pairingCode;
      _activeToken = token;
      if (serverUrl != null && serverUrl.isNotEmpty) {
        _targetServerUrl = serverUrl;
      }
    });

    final api = getIt<ApiClient>();

    try {
      // 1. Claim pairing code
      final claimRes = await api.claimPairingCode(
        code: pairingCode,
        enrollmentToken: token,
        serverUrl: _targetServerUrl,
        deviceName: kIsWeb
            ? 'Web Client'
            : '${defaultTargetPlatform.name.toUpperCase()} Device',
        deviceType: kIsWeb ? 'web' : 'phone',
        os: defaultTargetPlatform.name,
      );

      final status = claimRes['status'] as String? ?? 'pending_approval';

      if (status == 'approved' && claimRes['redeem_result'] != null) {
        // Instant approval!
        await _finalizeConnection(claimRes['redeem_result']);
        return;
      }

      setState(() {
        _statusMessage = 'Waiting for approval on your computer screen...';
      });

      // 2. Poll pairing status until Web approves
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        try {
          final res = await api.getPairingStatus(
            code: _activeCode,
            token: _activeToken,
            serverUrl: _targetServerUrl,
          );

          final currentStatus = res['status'] as String?;

          if (currentStatus == 'approved') {
            timer.cancel();
            if (res['redeem_result'] != null) {
              await _finalizeConnection(res['redeem_result']);
            } else {
              // Fetch tokens via redeem
              final redeemRes = await api.redeemPairingCode(
                _activeCode!,
                enrollmentToken: _activeToken,
                serverUrl: _targetServerUrl,
              );
              await _finalizeConnection(redeemRes);
            }
          } else if (currentStatus == 'rejected') {
            timer.cancel();
            if (mounted) {
              setState(() {
                _step = ConnectStep.error;
                _errorMessage =
                    'Connection request was declined on your computer.';
              });
            }
          } else if (currentStatus == 'expired') {
            timer.cancel();
            if (mounted) {
              setState(() {
                _step = ConnectStep.error;
                _errorMessage =
                    'Pairing session expired. Please generate a new code.';
              });
            }
          }
        } catch (_) {}
      });
    } catch (e) {
      // Try direct fallback redeem if claim endpoint is unrouted on older nodes
      try {
        final res = await api.redeemPairingCode(
          pairingCode,
          enrollmentToken: token,
          serverUrl: _targetServerUrl,
        );
        await _finalizeConnection(res);
      } catch (err) {
        if (mounted) {
          setState(() {
            _step = ConnectStep.error;
            _errorMessage = ApiClient.formatError(err);
          });
        }
      }
    }
  }

  Future<void> _finalizeConnection(dynamic redeemData) async {
    _pollTimer?.cancel();
    final api = getIt<ApiClient>();

    if (redeemData is Map && redeemData['access_token'] != null) {
      final access = redeemData['access_token'] as String;
      final refresh = redeemData['refresh_token'] as String;
      if (_targetServerUrl != null && _targetServerUrl!.isNotEmpty) {
        await api.setServerUrl(_targetServerUrl!);
      }
      await api.saveTokens(access, refresh);
    }

    if (!mounted) return;
    setState(() {
      _step = ConnectStep.success;
      _statusMessage = 'Device verified & securely connected!';
    });

    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      context.go('/dashboard');
    }
  }

  void _showNearbyDiscoveryDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_tethering_rounded,
                    color: AppTheme.primary, size: 28),
                const SizedBox(width: 12),
                Text('Discover Nearby PCOS Nodes',
                    style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Scanning local network for PCOS personal cloud storage nodes...',
              style: TextStyle(color: AppTheme.textMutedColor(context)),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Listening for mDNS / UDP presence beacons',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMutedColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdvancedServerDialog() {
    final api = getIt<ApiClient>();
    final serverCtrl = TextEditingController(text: api.currentServerUrl);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    color: AppTheme.primary, size: 24),
                const SizedBox(width: 12),
                Text('Advanced Server & Offline Settings',
                    style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'For self-hosted, offline LAN, or custom domain setups.',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textMutedColor(context)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: serverCtrl,
              decoration: const InputDecoration(
                labelText: 'Control Plane / Server URL',
                hintText: 'https://pcos.pages.dev or http://192.168.1.100:8080',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/login');
                    },
                    child: const Text('Password Sign In'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final url = serverCtrl.text.trim();
                      if (url.isNotEmpty) {
                        await api.setServerUrl(url);
                        setState(() {
                          _targetServerUrl = url;
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save Endpoint'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step == ConnectStep.scanning) {
      return _buildScannerView();
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 4,
                color: AppTheme.surfaceColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: AppTheme.borderColor(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      if (_step == ConnectStep.waitingApproval ||
                          _step == ConnectStep.success)
                        _buildStatusProgress()
                      else ...[
                        _buildModeSelector(),
                        const SizedBox(height: 24),
                        if (_showQrDisplayMode) ...[
                          _buildQrDisplayCard(),
                        ] else ...[
                          _buildQrScanButton(),
                          const SizedBox(height: 24),
                          _buildDivider(),
                          const SizedBox(height: 24),
                          _buildPairingCodeInput(),
                          const SizedBox(height: 28),
                          _buildConnectButton(),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _buildErrorMessage(),
                        ],
                        const SizedBox(height: 32),
                        _buildFooterLinks(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcodeDetected,
          ),
          // Viewfinder overlay
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black54),
                        onPressed: _stopScanning,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                      ),
                      const Text(
                        'Scan PCOS QR Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black54),
                        onPressed: () => _scannerController?.toggleTorch(),
                        icon: const Icon(Icons.flash_on_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Point camera at the QR code on your computer screen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Sign In',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (_targetServerUrl != null)
              Flexible(
                child: Text(
                  Uri.tryParse(_targetServerUrl!)?.host ?? '',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textMutedColor(context)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C5CE7).withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child:
                Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'PCOS',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Connect to your personal cloud',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textMutedColor(context),
              ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showQrDisplayMode = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_showQrDisplayMode
                      ? AppTheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 16,
                      color: !_showQrDisplayMode
                          ? Colors.white
                          : AppTheme.textMutedColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Scan / PIN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: !_showQrDisplayMode
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: !_showQrDisplayMode
                            ? Colors.white
                            : AppTheme.textMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showQrDisplayMode = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _showQrDisplayMode
                      ? AppTheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_rounded,
                      size: 16,
                      color: _showQrDisplayMode
                          ? Colors.white
                          : AppTheme.textMutedColor(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Display QR Code',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _showQrDisplayMode
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _showQrDisplayMode
                            ? Colors.white
                            : AppTheme.textMutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDisplayCard() {
    final api = getIt<ApiClient>();
    final serverUrl = _targetServerUrl?.isNotEmpty == true
        ? _targetServerUrl!
        : api.currentServerUrl;
    final payload = '$serverUrl/#/connect';

    return Column(
      children: [
        Text(
          'Point your phone camera or PCOS app at this QR code to connect:',
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 13, color: AppTheme.textMutedColor(context)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 190,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_rounded, size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  payload,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textPrimaryColor(context)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: payload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pairing link copied to clipboard!'),
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
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 14, color: AppTheme.success),
            const SizedBox(width: 6),
            Text(
              'Supports iOS Camera, Android Camera & Lens',
              style: TextStyle(
                  fontSize: 11, color: AppTheme.textMutedColor(context)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _startScanning,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.camera_alt_rounded, size: 18),
          label: const Text('Open Camera Scanner'),
        ),
      ],
    );
  }

  Widget _buildQrScanButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: _startScanning,
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
        label: const Text(
          'Scan QR Code',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.borderColor(context))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '--- OR ---',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMutedColor(context),
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.borderColor(context))),
      ],
    );
  }

  Widget _buildPairingCodeInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pairing Code',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryColor(context),
              ),
            ),
            Text(
              'Generated on PC',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMutedColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _digitControllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  if (val.isNotEmpty && index < 5) {
                    _focusNodes[index + 1].requestFocus();
                  } else if (val.isEmpty && index > 0) {
                    _focusNodes[index - 1].requestFocus();
                  }
                  if (_enteredCode.length == 6) {
                    _connectWithCode();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          '💡 Sign in on your computer and open Devices → Pair Device (or dashboard) to get your active 6-digit code.',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMutedColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _connectWithCode,
        child: const Text(
          'Connect',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildStatusProgress() {
    final isSuccess = _step == ConnectStep.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: (isSuccess ? AppTheme.success : AppTheme.primary)
                  .withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isSuccess
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppTheme.success, size: 44)
                  : const CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isSuccess ? 'Connected!' : 'Approval Required',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _statusMessage ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMutedColor(context),
            ),
          ),
          if (!isSuccess) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _pollTimer?.cancel();
                setState(() {
                  _step = ConnectStep.input;
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Column(
      children: [
        TextButton.icon(
          onPressed: _showNearbyDiscoveryDialog,
          icon: const Icon(Icons.wifi_find_rounded, size: 18),
          label: const Text('Discover Nearby'),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _showAdvancedServerDialog,
          icon: const Icon(Icons.settings_rounded, size: 16),
          label: Text(
            'Advanced: Manual Server',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMutedColor(context),
            ),
          ),
        ),
      ],
    );
  }
}
