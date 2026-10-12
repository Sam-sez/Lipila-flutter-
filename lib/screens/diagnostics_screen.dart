import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../diagnostics/app_log.dart';
import '../ble/bong_ble_service.dart';

/// Reachable via the bug icon in the Bong screen app-bar.
///
/// Provides:
///   Run diagnostics  — prints SDK level, BT adapter state, peripheral support
///   Request BLE perms — calls BongBleService.requestPermissions() and logs each result
///   Test advertise   — starts advertising for 5 s then stops; logs start/stop/error
///   Test scan        — scans for 8 s, logs device counts
///   Copy all         — copies the full AppLog to the clipboard
///   Clear            — clears the log buffer
///
/// Nothing here changes BLE logic; it only calls the same methods that
/// bong_screen.dart calls, but one-at-a-time so failures are isolated.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final BongBleService _ble = BongBleService();
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

  Future<void> _runDiagnostics() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('DIAG', '=== Run diagnostics ===');
    try {
      // Android SDK level
      final info = await DeviceInfoPlugin().androidInfo;
      AppLog.add('DIAG', 'Device: ${info.manufacturer} ${info.model}');
      AppLog.add('DIAG', 'Android SDK: ${info.version.sdkInt}  release: ${info.version.release}');
    } catch (e) {
      AppLog.add('DIAG', 'device_info_plus error: $e');
    }

    // BT adapter state — query via flutter_blue_plus without importing it
    // directly here; BongBleService exposes what we need.
    try {
      final adapterOn = await _ble.isBluetoothOn();
      AppLog.add('DIAG', 'Bluetooth adapter on: $adapterOn');
    } catch (e) {
      AppLog.add('DIAG', 'Adapter state error: $e');
    }

    // Peripheral support
    try {
      final supported = await _ble.isPeripheralSupported();
      AppLog.add('DIAG', 'Peripheral (advertise) supported: $supported');
    } catch (e) {
      AppLog.add('DIAG', 'Peripheral support check error: $e');
    }

    AppLog.add('DIAG', '=== Done ===');
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _requestPerms() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('PERM', '=== Request BLE permissions ===');
    try {
      final result = await _ble.requestPermissions();
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

  Future<void> _testAdvertise() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('ADV', '=== Test advertise (5 s) ===');
    const testUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    try {
      await _ble.startAdvertising(testUuid);
      AppLog.add('ADV', 'startAdvertising OK');
      await Future<void>.delayed(const Duration(seconds: 5));
      await _ble.stopAdvertising();
      AppLog.add('ADV', 'stopAdvertising OK');
    } catch (e, st) {
      AppLog.add('ADV', 'Exception type: ${e.runtimeType}');
      AppLog.add('ADV', 'Exception: $e');
      AppLog.add('ADV', 'Stack: $st');
    }
    setState(() => _busy = false);
    _refresh();
  }

  Future<void> _testScan() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLog.add('SCAN', '=== Test scan (8 s) ===');
    int total = 0;
    int withUuid = 0;
    StreamSubscription<List<BongDetectedDevice>>? sub;
    try {
      await _ble.startScanning();
      AppLog.add('SCAN', 'startScan OK');
      sub = _ble.detectedStream.listen((devices) {
        // Count totals via the raw BongDetectedDevice list
        withUuid = devices.length;
      });
      // Also hook raw scan result count via the service's exposed counter
      await Future<void>.delayed(const Duration(seconds: 8));
      await sub.cancel();
      await _ble.stopScanning();
      AppLog.add('SCAN', 'Scan results: withServiceUuid=$withUuid  (raw total logged by BongBleService)');
      AppLog.add('SCAN', 'stopScan OK');
    } catch (e, st) {
      await sub?.cancel();
      AppLog.add('SCAN', 'Exception type: ${e.runtimeType}');
      AppLog.add('SCAN', 'Exception: $e');
      AppLog.add('SCAN', 'Stack: $st');
    }
    setState(() => _busy = false);
    _refresh();
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
    AppLog.init(); // re-stamp build id and mode
    _refresh();
  }

  @override
  void dispose() {
    _ble.dispose();
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
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          // Action buttons
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
                  label: 'Request BLE perms',
                  icon: Icons.bluetooth,
                  busy: _busy,
                  onTap: _requestPerms,
                ),
                _ActionChip(
                  label: 'Test advertise (5 s)',
                  icon: Icons.settings_bluetooth,
                  busy: _busy,
                  onTap: _testAdvertise,
                ),
                _ActionChip(
                  label: 'Test scan (8 s)',
                  icon: Icons.radar,
                  busy: _busy,
                  onTap: _testScan,
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          const Divider(height: 1),
          // Log output
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
                      // Colour-code by tag for readability
                      Color? color;
                      if (line.contains('[PERM]')) color = Colors.orange.shade700;
                      if (line.contains('[ADV]')) color = Colors.blue.shade700;
                      if (line.contains('[SCAN]')) color = Colors.green.shade700;
                      if (line.contains('[ERR]')) color = Colors.red.shade700;
                      if (line.contains('[BUILD]')) color = Colors.purple.shade700;
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
