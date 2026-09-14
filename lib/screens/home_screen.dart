import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../state/auth_provider.dart';
import '../api/qr_api.dart';
import '../theme/lipila_theme.dart';
import '../widgets/action_button.dart';
import 'scan_screen.dart';
import 'request_screen.dart';
import 'bong_screen.dart';
import 'agent_tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _qrApi = QrApi();
  StaticQrResult? _staticQr;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _qrApi.getStatic(user.id).then((r) => setState(() => _staticQr = r));
  }

  Future<void> _exportPdf(String displayName, String maskedNumber) async {
    if (_staticQr == null) return;
    final qrBytes = base64Decode(_staticQr!.qrImage.split(',').last);
    final qrImage = pw.MemoryImage(qrBytes);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(320, 440),
        build: (ctx) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text('Lipila', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.Image(qrImage, width: 180, height: 180),
            pw.SizedBox(height: 16),
            pw.Text(displayName, style: const pw.TextStyle(fontSize: 17)),
            pw.SizedBox(height: 4),
            pw.Text(maskedNumber, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            pw.SizedBox(height: 30),
            pw.Text('Scan to pay via Lipila', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: 'lipila-qr-$displayName.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user!;
    final displayName = user.displayName;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hi, ${displayName.split(' ').first}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: LipilaColors.espresso)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${user.maskedNumber} · ${user.provider}', style: const TextStyle(color: Colors.grey)),
            if (user.isAgent) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: LipilaColors.line), borderRadius: BorderRadius.circular(100)),
                child: const Text('Agent', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LipilaColors.paperDim,
              border: const Border(left: BorderSide(color: LipilaColors.ember, width: 3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Lipila never holds your money. Every payment moves directly through ${user.provider} MoMo.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B5A44))),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Your QR', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 10),
                if (_staticQr != null)
                  Image.memory(base64Decode(_staticQr!.qrImage.split(',').last), width: 180, height: 180)
                else
                  const SizedBox(height: 180, width: 180, child: Center(child: CircularProgressIndicator())),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _staticQr == null ? null : () => _exportPdf(displayName, user.maskedNumber),
                  child: const Text('Export as PDF'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const SizedBox(height: 12),
          LipilaActionButton(label: 'Scan to pay', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()))),
          const SizedBox(height: 12),
          LipilaActionButton(label: 'Request payment', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestScreen()))),
          const SizedBox(height: 12),
          LipilaActionButton(label: 'Bong (nearby)', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BongScreen()))),
          if (user.isAgent) ...[
            const SizedBox(height: 12),
            LipilaActionButton(
              label: 'Agent tools', secondary: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentToolsScreen())),
            ),
          ],
        ],
      ),
    );
  }
}
