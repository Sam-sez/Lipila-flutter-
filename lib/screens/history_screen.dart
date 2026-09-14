import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import '../api/payments_api.dart';
import '../models/transaction.dart';
import '../theme/lipila_theme.dart';

const _methodLabels = {
  'static_qr': 'Static QR', 'dynamic_qr': 'Dynamic QR', 'bong': 'Bong', 'favorite': 'Favorite',
};

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _paymentsApi = PaymentsApi();
  List<LipilaTransaction> _txns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final userId = context.read<AuthProvider>().user!.id;
    try {
      final txns = await _paymentsApi.history(userId);
      if (!mounted) return;
      setState(() { _txns = txns; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = "Couldn't load your history — check your connection."; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.read<AuthProvider>().user!.id;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: LipilaColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_txns.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No transactions yet. Payments you send or receive will show up here.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _txns.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: LipilaColors.line),
      itemBuilder: (ctx, i) {
        final t = _txns[i];
        final outgoing = t.payerId == userId;
        return ListTile(
          title: Row(children: [
            Text(outgoing ? 'Sent' : 'Received', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (t.autoTag != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(border: Border.all(color: LipilaColors.line), borderRadius: BorderRadius.circular(100)),
                child: Text(t.autoTag!, style: const TextStyle(fontSize: 10)),
              ),
            ],
          ]),
          subtitle: Text('${t.note ?? "No note"} · ${_methodLabels[t.method] ?? t.method} · ${t.status}'),
          trailing: Text(
            '${outgoing ? "-" : "+"}K${t.amount.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: outgoing ? LipilaColors.danger : LipilaColors.success),
          ),
        );
      },
    );
  }
}
