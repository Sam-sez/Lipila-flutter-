import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../state/auth_provider.dart';
import '../api/qr_api.dart';
import '../models/display_identity.dart';
import '../theme/lipila_theme.dart';
import '../widgets/pay_confirm_sheet.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _qrApi = QrApi();
  final MobileScannerController _controller = MobileScannerController();
  bool _handledOnce = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledOnce) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;

    final match = RegExp(r'lipila://(static|dynamic)/([\w-]+)').firstMatch(value);
    if (match == null) {
      setState(() => _error = "That doesn't look like a Lipila QR code.");
      return;
    }
    _handledOnce = true;
    await _controller.stop();

    final kind = match.group(1)!;
    final token = match.group(2)!;
    await _resolve(kind, token);
  }

  Future<void> _resolve(String kind, String token) async {
    final payerId = context.read<AuthProvider>().user!.id;
    try {
      if (kind == 'static') {
        final identity = await _qrApi.resolveStatic(token);
        if (!mounted) return;
        await showPayConfirmSheet(context: context, payerId: payerId, payee: identity, method: 'static_qr');
      } else {
        final resolved = await _qrApi.resolveDynamic(token);
        if (!mounted) return;
        await showPayConfirmSheet(
          context: context, payerId: payerId, payee: resolved.payee,
          lockedAmount: resolved.amount, method: 'dynamic_qr',
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not resolve this QR code — it may have expired.');
    } finally {
      _handledOnce = false;
      _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to pay')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: LipilaColors.danger)),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Point your camera at a Static or Dynamic Lipila QR code.', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
