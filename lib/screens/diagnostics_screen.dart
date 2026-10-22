import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../diagnostics/app_log.dart';
import '../nfc/bong_nfc_service.dart';

/// Reachable via the bug icon in the Bong screen app-bar.
///
/// Buttons (all non-destructive, all logged to AppLog):
///   Run diagnostics  — SDK level, NFC availability, HCE support
///   Request NFC perms — checks NFC state and logs the result
///   Test emulate (10 s) — starts HCE for 10 s then stops; logs errors
///   Test read (tap)   — enters reader mode; shows what token it reads
///   Copy all          — copies full AppLog to clipboard
///   Clear             — clears log buffer and re-stamps build info
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final BongNfcService _nfc = BongNfcService();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  List<String> _logSnapshot = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _logSnapshot = AppLog.lines.toList());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _runDiagnostics() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('DIAG', '=== Run diagnostics ===');

    // Device info
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      AppLog.add('DIAG', 'Device: ${info.manufacturer} ${info.model}');
      AppLog.add('DIAG',
          'Android SDK: ${info.version.sdkInt}  release: ${info.version.release}');
    } catch (e) {
      AppLog.add('DIAG', 'device_info error: $e');
    }

    // NFC availability
    try {
      final avail = await _nfc.checkAvailability();
      AppLog.add('DIAG', 'NFC availability: $avail');
    } catch (e) {
      AppLog.add('DIAG', 'NFC availability error: $e');
    }

    // HCE support
    try {
      final hce = await _nfc.isHceSupported();
      AppLog.add('DIAG', 'HCE (emulator) supported: $hce');
    } catch (e) {
      AppLog.add('DIAG', 'HCE support check error: $e');
    }

    AppLog.add('DIAG', '=== Done ===');
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _requestPerms() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('PERM', '=== NFC permission check ===');
    try {
      final result = await _nfc.requestPermissions();
      AppLog.add('PERM', 'allGranted: ${result.allGranted}');
      AppLog.add('PERM', 'permanentlyDenied: ${result.permanentlyDenied}');
      for (final e in result.statuses.entries) {
        AppLog.add('PERM', '${e.key}: ${e.value}');
      }
    } catch (e, st) {
      AppLog.add('PERM', 'Exception: $e');
      AppLog.add('PERM', 'Stack: $st');
    }
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _testEmulate() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('NFC', '=== Test emulate (10 s) ===');
    const testToken = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    try {
      await _nfc.startEmulating(testToken);
      AppLog.add('NFC', 'startEmulating OK — holding for 10 s');
      await Future<void>.delayed(const Duration(seconds: 10));
      await _nfc.stopEmulating();
      AppLog.add('NFC', 'stopEmulating OK');
    } catch (e, st) {
      AppLog.add('NFC', 'Exception type: ${e.runtimeType}');
      AppLog.add('NFC', 'Exception: $e');
      AppLog.add('NFC', 'Stack: $st');
      await _nfc.stopEmulating(); // best-effort cleanup
    }
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _testRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('NFC', '=== Test read — tap a Bong device ===');
    try {
      await _nfc.startReading(
        onTokenRead: (token) {
          AppLog.add('NFC', 'TEST READ OK — token=$token');
          if (mounted) {
            setState(() => _busy = false);
            _refresh();
          }
        },
        onError: (msg) {
          AppLog.add('NFC', 'TEST READ error: $msg');
          if (mounted) {
            setState(() => _busy = false);
            _refresh();
          }
        },
      );
      // startReading returns as soon as the session is open — we stay busy
      // until onTokenRead or onError fires. If neither fires after 30 s,
      // stop the session so the diagnostic doesn't hang.
      await Future<void>.delayed(const Duration(seconds: 30));
      if (_busy) {
        await _nfc.stopReading();
        AppLog.add('NFC', 'TEST READ timeout (30 s) — no tap detected');
        if (mounted) setState(() => _busy = false);
        _refresh();
      }
    } catch (e, st) {
      AppLog.add('NFC', 'startReading exception: type=${e.runtimeType} err=$e');
      AppLog.add('NFC', 'Stack: $st');
      await _nfc.stopReading();
      if (mounted) setState(() => _busy = false);
      _refresh();
    }
  }

  Future<void> _copyAll() async {
    final text = '=== Lipila diagnostics ===\n${AppLog.dump()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log copied to clipboard')),
      );
    }
  }

  void _clear() {
    AppLog.clear();
    AppLog.init();
    _refresh();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nfc.stopEverything();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _busy ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionChip(
                  label: 'Run diagnostics',
                  icon: Icons.bug_report_outlined,
                  busy: _busy,
                  onTap: _runDiagnostics,
                ),
                _ActionChip(
                  label: 'Check NFC perms',
                  icon: Icons.nfc,
                  busy: _busy,
                  onTap: _requestPerms,
                ),
                _ActionChip(
                  label: 'Test emulate (10 s)',
                  icon: Icons.contactless_outlined,
                  busy: _busy,
                  onTap: _testEmulate,
                ),
                _ActionChip(
                  label: 'Test read (tap)',
                  icon: Icons.sensors,
                  busy: _busy,
                  onTap: _testRead,
                ),
              ],
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(),
          const Divider(height: 1),
          Expanded(
            child: _logSnapshot.isEmpty
                ? const Center(
                    child: Text(
                      'No log entries yet.\nTap "Run diagnostics" to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logSnapshot.length,
                    itemBuilder: (context, i) {
                      final line = _logSnapshot[i];
                      Color? color;
                      if (line.contains('[PERM]')) color = Colors.orange.shade700;
                      if (line.contains('[NFC]'))  color = Colors.blue.shade700;
                      if (line.contains('[ERR]'))  color = Colors.red.shade700;
                      if (line.contains('[BUILD]')) color = Colors.purple.shade700;
                      if (line.contains('[DIAG]')) color = Colors.teal.shade700;
                      return SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: color,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: busy ? null : onTap,
    );
  }
}
