import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/bong_api.dart';
import '../models/display_identity.dart';
import '../nfc/bong_nfc_service.dart';
import '../theme/lipila_theme.dart';
import '../widgets/pay_confirm_sheet.dart';
import 'diagnostics_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BongScreen — NFC asymmetric proximity payment
//
// UX model:
//   The screen opens with a role picker: PAY or RECEIVE.
//
//   PAYEE  taps RECEIVE → phone starts HCE emulation with their session token.
//          They hold their phone for the payer to tap. A "Ready to receive"
//          indicator shows while emulating. Auto-stops after 60 s.
//
//   PAYER  taps PAY → phone enters NFC reader mode. "Tap the other phone"
//          prompt appears. When they tap, the token is read, /reveal is called,
//          identity is shown, and showPayConfirmSheet runs. Auto-stops after 60 s.
//
// Fallback: if the device has no NFC (or NFC is off), a banner explains this
// and offers to open NFC settings. QR scan is always available as an
// alternative — this screen does not link to it but the bottom nav does.
// ─────────────────────────────────────────────────────────────────────────────

/// Which role this device is currently playing.
enum _BongRole { none, paying, receiving }

class BongScreen extends StatefulWidget {
  const BongScreen({super.key});

  @override
  State<BongScreen> createState() => _BongScreenState();
}

class _BongScreenState extends State<BongScreen> {
  final _bongApi = BongApi();
  final _nfc = BongNfcService();

  _BongRole _role = _BongRole.none;
  NfcAvailabilityState _nfcAvail = NfcAvailabilityState.unknown;
  bool _checkingAvailability = true;

  String? _mySessionToken;
  String? _error;
  bool _sessionActive = false;
  Timer? _expiryTimer;

  // ─── Lifecycle ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _nfc.stopEverything();
    super.dispose();
  }

  // ─── NFC availability check ───────────────────────────────────────────

  Future<void> _checkNfc() async {
    setState(() => _checkingAvailability = true);
    final avail = await _nfc.checkAvailability();
    if (mounted) {
      setState(() {
        _nfcAvail = avail;
        _checkingAvailability = false;
      });
    }
  }

  // ─── RECEIVE role (payee — HCE emulator) ─────────────────────────────

  Future<void> _startReceiving() async {
    setState(() { _error = null; });

    final permResult = await _nfc.requestPermissions();
    if (!permResult.allGranted) {
      setState(() {
        _error = permResult.permanentlyDenied
            ? 'This device does not support NFC. Use QR scan instead.'
            : 'NFC is turned off. Enable it in Settings to use Bong.';
      });
      return;
    }

    final userId = context.read<AuthProvider>().user!.id;
    final token = _nfc.generateSessionToken();

    // Announce to backend before emulating so the token is registered.
    try {
      await _bongApi.announce(userId, token);
    } catch (e) {
      setState(() => _error = 'Could not reach the server. Check your connection.');
      return;
    }

    try {
      await _nfc.startEmulating(token);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    setState(() {
      _mySessionToken = token;
      _role = _BongRole.receiving;
      _sessionActive = true;
    });

    _startExpiryTimer();
  }

  // ─── PAY role (payer — NFC reader) ───────────────────────────────────

  Future<void> _startPaying() async {
    setState(() { _error = null; });

    final permResult = await _nfc.requestPermissions();
    if (!permResult.allGranted) {
      setState(() {
        _error = permResult.permanentlyDenied
            ? 'This device does not support NFC. Use QR scan instead.'
            : 'NFC is turned off. Enable it in Settings to use Bong.';
      });
      return;
    }

    setState(() {
      _role = _BongRole.paying;
      _sessionActive = true;
    });

    _startExpiryTimer();

    try {
      await _nfc.startReading(
        onTokenRead: _handleTokenRead,
        onError: (msg) {
          if (mounted) setState(() => _error = msg);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _role = _BongRole.none;
          _sessionActive = false;
        });
        _expiryTimer?.cancel();
      }
    }
  }

  // ─── Token read handler (payer) ───────────────────────────────────────

  Future<void> _handleTokenRead(String token) async {
    setState(() { _error = null; });
    try {
      final identity = await _bongApi.reveal(token);
      if (!mounted) return;
      await _closeBong();
      if (!mounted) return;
      final userId = context.read<AuthProvider>().user!.id;
      await showPayConfirmSheet(
        context: context,
        payerId: userId,
        payee: identity,
        method: 'bong',
      );
    } on _BongRevealException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not confirm identity — the session may have expired. Try again.');
      }
    }
  }

  // ─── Session close ────────────────────────────────────────────────────

  Future<void> _closeBong() async {
    _expiryTimer?.cancel();
    await _nfc.stopEverything();
    if (mounted) {
      setState(() {
        _role = _BongRole.none;
        _sessionActive = false;
        _mySessionToken = null;
      });
    }
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _sessionActive) {
        _closeBong();
        if (mounted) {
          setState(() => _error = 'Session expired after 60 seconds. Tap to start again.');
        }
      }
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bong'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Diagnostics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _checkingAvailability
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // ── NFC unavailable states ───────────────────────────────────────────
    if (_nfcAvail == NfcAvailabilityState.notSupported) {
      return _NfcUnavailableBanner(
        title: 'NFC not supported',
        message:
            'This device has no NFC hardware. Use QR scan instead — '
            'tap the scan icon in the bottom bar.',
        showSettingsButton: false,
        onRetry: null,
      );
    }

    if (_nfcAvail == NfcAvailabilityState.disabled) {
      return _NfcUnavailableBanner(
        title: 'NFC is turned off',
        message: 'Enable NFC in your device settings to use Bong.',
        showSettingsButton: true,
        onOpenSettings: () async {
          await _nfc.openSettings();
          // Re-check after returning from settings.
          await Future<void>.delayed(const Duration(seconds: 1));
          _checkNfc();
        },
        onRetry: _checkNfc,
      );
    }

    // ── Active session ────────────────────────────────────────────────────
    if (_role == _BongRole.receiving) return _buildReceivingView();
    if (_role == _BongRole.paying)    return _buildPayingView();

    // ── Role picker ──────────────────────────────────────────────────────
    return _buildRolePicker();
  }

  Widget _buildRolePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pay someone nearby — just tap phones.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose your role for this transaction:',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        // PAY button
        ElevatedButton.icon(
          icon: const Icon(Icons.nfc, color: Colors.white),
          label: const Text(
            'I\'m paying',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          onPressed: _startPaying,
          style: ElevatedButton.styleFrom(
            backgroundColor: LipilaColors.ember,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        // RECEIVE button
        OutlinedButton.icon(
          icon: const Icon(Icons.contactless_outlined),
          label: const Text('I\'m receiving', style: TextStyle(fontSize: 16)),
          onPressed: _startReceiving,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            side: const BorderSide(color: LipilaColors.ember, width: 1.5),
            foregroundColor: LipilaColors.ember,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LipilaColors.paperDim,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'How it works: the receiver holds their phone still. '
            'The payer taps their phone against the receiver\'s. '
            'Identity is revealed only after you confirm payment.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBox(message: _error!, onDismiss: () => setState(() => _error = null)),
        ],
      ],
    );
  }

  Widget _buildReceivingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _NfcAnimatedIcon(),
        const SizedBox(height: 20),
        const Text(
          'Ready to receive',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hold your phone steady. Ask the payer to tap their phone against yours.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        const Text(
          'Session expires in ~60 seconds.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _closeBong,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: const Text('Cancel'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBox(message: _error!, onDismiss: () => setState(() => _error = null)),
        ],
      ],
    );
  }

  Widget _buildPayingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _NfcAnimatedIcon(),
        const SizedBox(height: 20),
        const Text(
          'Tap the other phone',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hold your phone against the receiver\'s phone. '
          'Keep them close until you feel a vibration or see a confirmation.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        const Text(
          'Session expires in ~60 seconds.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _closeBong,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: const Text('Cancel'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBox(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
            // For read errors the user can just tap again — don't close the session.
            actionLabel: 'Try tapping again',
            onAction: () => setState(() => _error = null),
          ),
        ],
      ],
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

class _NfcAnimatedIcon extends StatefulWidget {
  const _NfcAnimatedIcon();

  @override
  State<_NfcAnimatedIcon> createState() => _NfcAnimatedIconState();
}

class _NfcAnimatedIconState extends State<_NfcAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _scale,
        child: Icon(Icons.nfc, size: 96, color: LipilaColors.ember),
      ),
    );
  }
}

class _NfcUnavailableBanner extends StatelessWidget {
  const _NfcUnavailableBanner({
    required this.title,
    required this.message,
    required this.showSettingsButton,
    this.onOpenSettings,
    this.onRetry,
  });

  final String title;
  final String message;
  final bool showSettingsButton;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.nfc_outlined, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        if (showSettingsButton && onOpenSettings != null)
          ElevatedButton(
            onPressed: onOpenSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: LipilaColors.ember,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Open NFC settings',
                style: TextStyle(color: Colors.white)),
          ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('Check again'),
          ),
        ],
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LipilaColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: LipilaColors.danger.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 16, color: LipilaColors.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: LipilaColors.danger, fontSize: 13)),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!,
                  style: const TextStyle(
                      color: LipilaColors.ember, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Internal exception type ──────────────────────────────────────────────────

class _BongRevealException implements Exception {
  final String message;
  const _BongRevealException(this.message);
}
