import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/bong_api.dart';
import '../models/display_identity.dart';
import '../ble/bong_ble_service.dart';
import '../theme/lipila_theme.dart';
import '../widgets/pay_confirm_sheet.dart';

class BongScreen extends StatefulWidget {
  const BongScreen({super.key});

  @override
  State<BongScreen> createState() => _BongScreenState();
}

class _BongScreenState extends State<BongScreen> {
  final _bongApi = BongApi();
  final _ble = BongBleService();
  StreamSubscription<List<BongDetectedDevice>>? _sub;

  String? _mySessionToken;
  bool _open = false;
  bool _permissionsDenied = false;
  bool _permissionsPermanentlyDenied = false;
  List<String> _missingPermissions = [];
  List<BongDetectedDevice> _detected = [];
  DisplayIdentity? _selected;
  String? _error;
  Timer? _postTimer;

  Future<void> _openBong() async {
    setState(() { _error = null; _permissionsDenied = false; _permissionsPermanentlyDenied = false; });

    final permissionResult = await _ble.requestPermissions();
    if (!permissionResult.allGranted) {
      setState(() {
        _permissionsDenied = true;
        _permissionsPermanentlyDenied = permissionResult.permanentlyDenied;
        _missingPermissions = permissionResult.missing;
      });
      return;
    }

    final userId = context.read<AuthProvider>().user!.id;
    final token = _ble.generateSessionToken();
    try {
      await _bongApi.announce(userId, token);
    } catch (e) {
      setState(() => _error = 'Could not start Bong — check your connection.');
      return;
    }

    setState(() { _mySessionToken = token; _open = true; });

    try {
      await _ble.startAdvertising(token);
      await _ble.startScanning();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _open = false; });
      return;
    }

    _sub = _ble.detectedStream.listen((snapshot) {
      setState(() => _detected = snapshot.where((d) => d.sessionToken != token).toList());
    });

    // Post the current detected set to the backend periodically — the
    // backend does the actual ranking/validity check against its own
    // announced tokens; we just forward what the radio saw.
    _postTimer = Timer.periodic(const Duration(seconds: 2), (_) => _postCandidates());

    // Auto-close after 60s regardless of a match, mirroring the backend TTL.
    Timer(const Duration(seconds: 60), () {
      if (mounted && _open && _selected == null) _closeBong();
    });
  }

  Future<void> _postCandidates() async {
    if (_detected.isEmpty) return;
    try {
      await _bongApi.candidates(_detected.map((d) => {
            'detected_session_token': d.sessionToken,
            'rssi': d.rssi,
          }).toList());
    } catch (_) {
      // Transient network hiccups here aren't fatal — the next tick retries.
    }
  }

  Future<void> _pick(String sessionToken) async {
    setState(() => _error = null);
    try {
      final identity = await _bongApi.reveal(sessionToken);
      await _closeBong();
      if (!mounted) return;
      final userId = context.read<AuthProvider>().user!.id;
      setState(() => _selected = identity);
      await showPayConfirmSheet(context: context, payerId: userId, payee: identity, method: 'bong');
      if (mounted) setState(() => _selected = null);
    } catch (e) {
      setState(() => _error = 'Could not confirm identity — the session may have expired.');
    }
  }

  Future<void> _closeBong() async {
    _postTimer?.cancel();
    await _sub?.cancel();
    await _ble.stopEverything();
    if (mounted) setState(() => _open = false);
  }

  @override
  void dispose() {
    _postTimer?.cancel();
    _sub?.cancel();
    _ble.stopEverything();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bong')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pay someone standing near you — no scanning, no typing a number.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            if (_permissionsDenied)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: LipilaColors.paperDim, borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _missingPermissions.isEmpty
                        ? 'Bong needs Bluetooth and location permissions to find nearby devices.'
                        : 'Missing: ${_missingPermissions.join(", ")}.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (_permissionsPermanentlyDenied) ...[
                    const Text(
                      "Android won't show the permission prompt again once denied — "
                      "open Settings to turn these on manually.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: () => _ble.openSettings(), child: const Text('Open app settings')),
                  ] else
                    OutlinedButton(onPressed: _openBong, child: const Text('Try again')),
                ]),
              ),
            if (!_open && _selected == null)
              ElevatedButton(
                onPressed: _openBong,
                style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
                child: const Text('Open Bong', style: TextStyle(color: Colors.white)),
              ),
            if (_open) ...[
              const SizedBox(height: 8),
              const Text('Advertising & scanning nearby…', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text('Expires in ~60 seconds, whether or not a match happens.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              if (_detected.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator())),
              ..._detected.asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final device = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => _pick(device.sessionToken),
                    child: Text(rank == 1 ? 'Closest device' : 'Nearby device #$rank'),
                  ),
                );
              }),
              const SizedBox(height: 8),
              TextButton(onPressed: _closeBong, child: const Text('Cancel')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: LipilaColors.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
