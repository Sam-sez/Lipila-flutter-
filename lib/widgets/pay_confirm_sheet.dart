import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../api/payments_api.dart';
import '../models/display_identity.dart';
import '../theme/lipila_theme.dart';

enum _Step { amount, biometric, pin, processing, done }

/// Shows the shared confirm flow as a modal bottom sheet. Every payment
/// entry point (Scan, Favorites, Bong) calls this the same way — none of
/// them are allowed to skip biometric or the PIN step, only the discovery
/// step that got them here.
Future<void> showPayConfirmSheet({
  required BuildContext context,
  required String payerId,
  required DisplayIdentity payee,
  double? lockedAmount, // non-null for Dynamic QR — user can't edit it
  required String method, // static_qr | dynamic_qr | bong | favorite
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PayConfirmSheet(
      payerId: payerId, payee: payee, lockedAmount: lockedAmount, method: method,
    ),
  );
}

class _PayConfirmSheet extends StatefulWidget {
  final String payerId;
  final DisplayIdentity payee;
  final double? lockedAmount;
  final String method;

  const _PayConfirmSheet({
    required this.payerId, required this.payee, this.lockedAmount, required this.method,
  });

  @override
  State<_PayConfirmSheet> createState() => _PayConfirmSheetState();
}

class _PayConfirmSheetState extends State<_PayConfirmSheet> {
  _Step _step = _Step.amount;
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _pinController = TextEditingController();
  bool _saveFavorite = true;
  String? _error;
  dynamic _resultTxn;
  final _paymentsApi = PaymentsApi();
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    if (widget.lockedAmount != null) {
      _amountController.text = widget.lockedAmount!.toStringAsFixed(2);
    }
  }

  Future<void> _runBiometric() async {
    setState(() => _step = _Step.biometric);
    try {
      // Real device-level biometric — this never touches provider funds,
      // it only authorizes the REQUEST inside Lipila, same as the web
      // version's (simulated) biometric step.
      final canCheck = await _localAuth.canCheckBiometrics;
      final ok = canCheck
          ? await _localAuth.authenticate(
              localizedReason: 'Confirm this payment',
              options: const AuthenticationOptions(biometricOnly: false),
            )
          : true; // devices with no biometric hardware fall through in this demo
      if (ok) {
        setState(() => _step = _Step.pin);
      } else {
        setState(() => _step = _Step.amount);
      }
    } catch (e) {
      setState(() { _error = 'Biometric check failed — try again.'; _step = _Step.amount; });
    }
  }

  Future<void> _submitPin() async {
    if (_pinController.text.length != 4) {
      setState(() => _error = 'Enter your 4-digit PIN.');
      return;
    }
    // This PIN is never sent to Lipila's backend — discarded right here.
    // In production this step IS the provider's own native prompt, not a
    // Lipila UI at all.
    _pinController.clear();
    setState(() { _error = null; _step = _Step.processing; });
    try {
      final txn = await _paymentsApi.confirmAndPoll(
        payerId: widget.payerId,
        payeeId: widget.payee.userId,
        amount: double.parse(_amountController.text),
        method: widget.method,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        saveAsFavorite: _saveFavorite,
      );
      setState(() { _resultTxn = txn; _step = _Step.done; });
    } catch (e) {
      setState(() { _error = 'Payment failed to process.'; _step = _Step.pin; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: LipilaColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(child: _buildStep(context)),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _Step.amount:
        return _buildAmountStep();
      case _Step.biometric:
        return _buildBiometricStep();
      case _Step.pin:
        return _buildPinStep();
      case _Step.processing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: Text('Processing with your provider…')),
        );
      case _Step.done:
        return _buildDoneStep();
    }
  }

  Widget _buildAmountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("You're paying", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Row(children: [
          CircleAvatar(
            backgroundColor: LipilaColors.paperDim,
            child: Text(widget.payee.name.isNotEmpty ? widget.payee.name[0].toUpperCase() : '?'),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.payee.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('✓ Verified · ···${widget.payee.verifiedNumberSuffix}',
                style: const TextStyle(color: LipilaColors.success, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          enabled: widget.lockedAmount == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (ZMW)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: LipilaColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text);
            if (amount == null || amount <= 0) {
              setState(() => _error = 'Enter an amount greater than zero.');
              return;
            }
            setState(() => _error = null);
            _runBiometric();
          },
          style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
          child: const Text('Continue', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildBiometricStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(height: 12),
        Icon(Icons.fingerprint, size: 48, color: LipilaColors.ember),
        SizedBox(height: 8),
        Text('Confirm with biometrics', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 6),
        Text('Authorizes this request inside Lipila only.', style: TextStyle(color: Colors.grey)),
        SizedBox(height: 16),
        CircularProgressIndicator(),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPinStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('MTN MoMo PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        const Text(
          'Sent by your provider directly, not Lipila. In mock mode this PIN is discarded here.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          decoration: const InputDecoration(counterText: ''),
        ),
        CheckboxListTile(
          value: _saveFavorite,
          onChanged: (v) => setState(() => _saveFavorite = v ?? true),
          title: Text('Save ${widget.payee.name} as a favorite'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: LipilaColors.danger, fontSize: 13)),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _submitPin,
          style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
          child: const Text('Authorize payment', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    final success = _resultTxn?.status == 'successful';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(success ? Icons.check_circle : Icons.error, size: 48, color: success ? LipilaColors.success : LipilaColors.danger),
        const SizedBox(height: 8),
        Text(success ? 'Payment sent' : 'Payment failed', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Text('K${(_resultTxn?.amount ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text('to ${widget.payee.name}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
          child: const Text('Done', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
