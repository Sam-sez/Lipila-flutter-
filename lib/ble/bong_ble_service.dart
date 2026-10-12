import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../diagnostics/app_log.dart';

/// Lipila's Bong protocol runs entirely over each device's own BLE Service
/// UUID. Every device advertises ONLY a random per-session UUID — no name,
/// no other payload — which is what keeps identity anonymous until a
/// specific match is chosen (see bong_screen.dart for the reveal step).
///
/// NOTE ON RISK: this file combines two separate plugins because no single
/// Flutter BLE package reliably does both central (scan) and peripheral
/// (advertise) roles at once. This is the single most likely file in the
/// whole project to need fixing against a real CI build error — package
/// APIs shift between versions and this was written from general knowledge
/// of both packages' shapes, not verified against a compiler. If the build
/// fails here, read the actual error (likely a renamed method/parameter)
/// and fix the specific call, not the whole architecture.
class BongDetectedDevice {
  final String sessionToken;
  final int rssi;
  BongDetectedDevice(this.sessionToken, this.rssi);
}

class BongPermissionResult {
  final bool allGranted;
  final bool permanentlyDenied;
  final Map<String, PermissionStatus> statuses;
  BongPermissionResult({
    required this.allGranted,
    required this.permanentlyDenied,
    required this.statuses,
  });

  /// Human-readable list of exactly which permissions are still missing —
  /// shown in the UI so "it's stuck" becomes "Bluetooth scan is denied",
  /// which is actually debuggable.
  List<String> get missing => statuses.entries
      .where((e) => !e.value.isGranted && !e.value.isLimited)
      .map((e) => e.key)
      .toList();
}

class BongBleService {
  static const _uuid = Uuid();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  final _detectedController =
      StreamController<List<BongDetectedDevice>>.broadcast();
  Stream<List<BongDetectedDevice>> get detectedStream =>
      _detectedController.stream;

  // Running totals exposed for diagnostics
  int _rawScanTotal = 0;
  int _rawScanWithUuid = 0;
  int get rawScanTotal => _rawScanTotal;
  int get rawScanWithUuid => _rawScanWithUuid;

  final Map<String, int> _seen = {}; // sessionToken -> latest RSSI seen

  /// This device's own session token, advertised as the BLE service UUID.
  String generateSessionToken() => _uuid.v4();

  // ─── Diagnostics helpers ────────────────────────────────────────────────

  /// Whether the Bluetooth adapter is currently powered on.
  /// Uses flutter_blue_plus's adapterState stream; takes the first value.
  Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState
          .timeout(const Duration(seconds: 3))
          .first;
      AppLog.add('DIAG', 'BT adapterState: $state');
      return state == BluetoothAdapterState.on;
    } catch (e) {
      AppLog.add('DIAG', 'adapterState error: $e');
      return false;
    }
  }

  /// Whether this hardware/OS supports BLE peripheral (advertising) mode.
  /// flutter_ble_peripheral exposes this as a Future<bool> via isSupported.
  Future<bool> isPeripheralSupported() async {
    try {
      // isSupported is a getter that returns Future<bool> on the peripheral
      // instance. We cast through dynamic to guard against API drift.
      final supported = await (_peripheral as dynamic).isSupported as bool;
      AppLog.add('DIAG', 'peripheral.isSupported: $supported');
      return supported;
    } catch (e) {
      AppLog.add('DIAG', 'isSupported error: $e');
      return false;
    }
  }

  // ─── Permissions ────────────────────────────────────────────────────────

  /// Requests every permission Bong needs and logs before/after/permanentlyDenied
  /// for each one. Returns a result the UI can act on directly.
  Future<BongPermissionResult> requestPermissions() async {
    final permissions = <String, Permission>{
      'Bluetooth advertise': Permission.bluetoothAdvertise,
      'Bluetooth scan': Permission.bluetoothScan,
      'Bluetooth connect': Permission.bluetoothConnect,
      'Location': Permission.locationWhenInUse,
    };
    final statuses = <String, PermissionStatus>{};

    for (final entry in permissions.entries) {
      PermissionStatus before;
      try {
        before = await entry.value.status;
      } catch (e) {
        before = PermissionStatus.denied;
      }
      AppLog.add('PERM', '${entry.key}: before=$before');

      PermissionStatus after;
      try {
        after = await entry.value.request();
      } catch (e) {
        AppLog.add('PERM', '${entry.key}: request() threw $e');
        after = PermissionStatus.denied;
      }

      final permDenied = after.isPermanentlyDenied;
      AppLog.add('PERM', '${entry.key}: after=$after  permanentlyDenied=$permDenied');
      statuses[entry.key] = after;
    }

    final allGranted =
        statuses.values.every((s) => s.isGranted || s.isLimited);
    final anyPermanentlyDenied =
        statuses.values.any((s) => s.isPermanentlyDenied);

    AppLog.add('PERM', 'allGranted=$allGranted  anyPermanentlyDenied=$anyPermanentlyDenied');

    return BongPermissionResult(
      allGranted: allGranted,
      permanentlyDenied: anyPermanentlyDenied,
      statuses: statuses,
    );
  }

  /// Opens the OS app-settings screen — only way forward once permanently denied.
  Future<void> openSettings() => openAppSettings();

  // ─── Advertise ──────────────────────────────────────────────────────────

  Future<void> startAdvertising(String sessionToken) async {
    AppLog.add('ADV', 'startAdvertising token=$sessionToken');
    try {
      final advertiseData = AdvertiseData(
        serviceUuid: sessionToken,
        includeDeviceName: false,
      );
      await _peripheral.start(advertiseData: advertiseData);
      AppLog.add('ADV', 'startAdvertising OK');
    } catch (e, st) {
      AppLog.add('ADV', 'startAdvertising FAILED: type=${e.runtimeType}  err=$e');
      AppLog.add('ADV', 'stack: $st');
      throw Exception(
          'Could not start advertising — is Bluetooth turned on? ($e)');
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _peripheral.stop();
      AppLog.add('ADV', 'stopAdvertising OK');
    } catch (e) {
      AppLog.add('ADV', 'stopAdvertising error (non-fatal): $e');
    }
  }

  // ─── Scan ────────────────────────────────────────────────────────────────

  Future<void> startScanning() async {
    _seen.clear();
    _rawScanTotal = 0;
    _rawScanWithUuid = 0;
    AppLog.add('SCAN', 'startScan called');
    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 60));
      AppLog.add('SCAN', 'startScan OK');
    } catch (e, st) {
      AppLog.add('SCAN', 'startScan FAILED: type=${e.runtimeType}  err=$e');
      AppLog.add('SCAN', 'stack: $st');
      throw Exception(
          'Could not start scanning — is Bluetooth turned on? ($e)');
    }

    // flutter_blue_plus ≥1.29: scanResults keeps previous-scan results too;
    // onScanResults clears between scans. We use scanResults here so that the
    // stream keeps emitting even if a scan cycle wraps — Bong needs continuous
    // updates for 60 s.
    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        _rawScanTotal += results.length;
        for (final r in results) {
          final serviceUuids = r.advertisementData.serviceUuids;
          if (serviceUuids.isEmpty) continue;
          _rawScanWithUuid++;
          // Guid.toString() returns the UUID string (lower-case, with hyphens)
          final token = serviceUuids.first.toString();
          _seen[token] = r.rssi;
        }
        if (results.isNotEmpty) {
          AppLog.add(
            'SCAN',
            'result batch: raw=${results.length}  withUuid=$_rawScanWithUuid  '
            'uniqueTokens=${_seen.length}',
          );
        }
        final snapshot = _seen.entries
            .map((e) => BongDetectedDevice(e.key, e.value))
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        _detectedController.add(snapshot);
      },
      onError: (Object e) {
        AppLog.add('SCAN', 'scanResults stream error: $e');
      },
    );
  }

  Future<void> stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
      AppLog.add('SCAN', 'stopScan OK  totalRaw=$_rawScanTotal  withUuid=$_rawScanWithUuid');
    } catch (e) {
      AppLog.add('SCAN', 'stopScan error (non-fatal): $e');
    }
  }

  Future<void> stopEverything() async {
    await stopScanning();
    await stopAdvertising();
  }

  void dispose() {
    _detectedController.close();
  }
}
