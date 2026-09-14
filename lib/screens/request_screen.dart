import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/qr_api.dart';
import '../theme/lipila_theme.dart';

class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final _qrApi = QrApi();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DynamicQrResult? _qr;
  Uint8List? _qrBytes; // decoded ONCE on generation, not on every rebuild
  int _secondsLeft = 0;
  Timer? _timer;
  String? _error;

  Future<void> _generate() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    setState(() => _error = null);
    final user = context.read<AuthProvider>().user!;
    try {
      final result = await _qrApi.createDynamic(user.id, amount, _noteController.text.isEmpty ? null : _noteController.text);
      final imageDataUri = await _qrApi.getDynamicImage(result.qrToken);
      // Decode exactly once here — the countdown timer below triggers a
      // rebuild every second, and decoding base64 inside build() on every
      // one of those rebuilds was what caused the visible flicker.
      final bytes = base64Decode(imageDataUri.split(',').last);
      setState(() { _qr = result; _qrBytes = bytes; _secondsLeft = result.expiresInSeconds; });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_secondsLeft <= 0) { t.cancel(); return; }
        setState(() => _secondsLeft--);
      });
    } catch (e) {
      setState(() => _error = 'Could not generate QR.');
    }
  }

  void _reset() {
    setState(() { _qr = null; _qrBytes = null; _amountController.clear(); _noteController.clear(); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _qr != null && _secondsLeft <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a payment')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _qr == null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Generates a Dynamic QR with the exact amount locked in — expires in a few minutes.',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(controller: _amountController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (ZMW)')),
                const SizedBox(height: 12),
                TextField(controller: _noteController,
                    decoration: const InputDecoration(labelText: "What's it for? (optional)")),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: LipilaColors.danger)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _generate,
                  style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
                  child: const Text('Generate QR', style: TextStyle(color: Colors.white)),
                ),
              ])
            : Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (!expired) ...[
                    Image.memory(_qrBytes!, width: 220, height: 220, gaplessPlayback: true),
                    const SizedBox(height: 12),
                    Text('K${_qr!.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('Expires in ${_secondsLeft}s', style: const TextStyle(color: Colors.grey)),
                  ] else ...[
                    const Icon(Icons.timer_off, size: 40, color: Colors.grey),
                    const Text('This QR has expired', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text("Generate a new one if the payer hasn't scanned yet.", style: TextStyle(color: Colors.grey)),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _reset, child: Text(expired ? 'Generate new QR' : 'Cancel request')),
                ]),
              ),
      ),
    );
  }
}
