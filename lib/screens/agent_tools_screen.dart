import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/agents_api.dart';
import '../api/qr_api.dart';
import '../models/display_identity.dart';
import '../theme/lipila_theme.dart';

class AgentToolsScreen extends StatefulWidget {
  const AgentToolsScreen({super.key});

  @override
  State<AgentToolsScreen> createState() => _AgentToolsScreenState();
}

class _AgentToolsScreenState extends State<AgentToolsScreen> {
  final _agentsApi = AgentsApi();
  final _qrApi = QrApi();
  final _tokenController = TextEditingController();
  final _amountController = TextEditingController();
  String _mode = 'cash-in';
  DisplayIdentity? _resolved;
  dynamic _result;
  String? _error;

  Future<void> _verify() async {
    setState(() { _error = null; _resolved = null; });
    if (_tokenController.text.trim().isEmpty) {
      setState(() => _error = "Enter the user's static QR token.");
      return;
    }
    try {
      final identity = await _qrApi.resolveStatic(_tokenController.text.trim());
      setState(() => _resolved = identity);
    } catch (e) {
      setState(() => _error = 'Could not resolve that QR code.');
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the cash amount.');
      return;
    }
    final agent = context.read<AuthProvider>().user!;
    try {
      final txn = _mode == 'cash-in'
          ? await _agentsApi.cashIn(agentId: agent.id, userQrToken: _tokenController.text.trim(), amount: amount)
          : await _agentsApi.cashOut(userId: _tokenController.text.trim(), agentQrToken: agent.staticQrToken, amount: amount);
      setState(() => _result = txn);
    } catch (e) {
      setState(() => _error = 'Transaction failed.');
    }
  }

  void _reset() {
    setState(() { _result = null; _resolved = null; _tokenController.clear(); _amountController.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    if (!user.isAgent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agent tools')),
        body: const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This section is only available to registered MoMo agent accounts.', textAlign: TextAlign.center),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Agent tools')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: LipilaColors.paperDim, borderRadius: BorderRadius.circular(6)),
            child: const Text(
              "Lipila records and confirms the digital transfer only — it can't verify or guarantee the physical cash handoff itself.",
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ChoiceChip(
              label: const Text('Cash-in'), selected: _mode == 'cash-in',
              onSelected: (_) => setState(() { _mode = 'cash-in'; _result = null; }),
            )),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(
              label: const Text('Cash-out'), selected: _mode == 'cash-out',
              onSelected: (_) => setState(() { _mode = 'cash-out'; _result = null; }),
            )),
          ]),
          const SizedBox(height: 16),
          if (_result == null) ...[
            Text(_mode == 'cash-in' ? "Scan user's QR (enter token)" : "User's QR token", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            TextField(controller: _tokenController, decoration: const InputDecoration(labelText: 'QR token')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _verify, child: const Text('Verify identity')),
            if (_resolved != null)
              ListTile(
                leading: CircleAvatar(child: Text(_resolved!.name.isNotEmpty ? _resolved!.name[0].toUpperCase() : '?')),
                title: Text(_resolved!.name),
                subtitle: Text('✓ ···${_resolved!.verifiedNumberSuffix}'),
              ),
            const SizedBox(height: 8),
            TextField(controller: _amountController, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cash amount (ZMW)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: LipilaColors.danger)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(backgroundColor: LipilaColors.ember, minimumSize: const Size.fromHeight(48)),
              child: Text(_mode == 'cash-in' ? 'Push funds to user' : 'Request payment from user', style: const TextStyle(color: Colors.white)),
            ),
          ] else
            Center(
              child: Column(children: [
                const Icon(Icons.check_circle, size: 40, color: LipilaColors.success),
                Text(_mode == 'cash-in' ? 'Cash-in recorded' : 'Cash-out requested', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('K${_result.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reset, child: const Text('New transaction')),
              ]),
            ),
        ]),
      ),
    );
  }
}
