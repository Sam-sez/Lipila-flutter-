import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

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
  BongPermissionResult({required this.allGranted, required this.permanentlyDenied, required this.statuses});

  /// Human-readable list of exactly which permissions are still missing —
  /// shown in the UI so "it's stuck" becomes "Bluetooth scan is denied",
  /// which is actually debuggable.
  List<String> get missing =>
      statuses.entries.where((e) => !e.value.isGranted && !e.value.isLimited).map((e) => e.key).toList();
}

class BongBleService {
  static const _uuid = Uuid();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  final _detectedController = StreamController<List<BongDetectedDevice>>.broadcast();
  Stream<List<BongDetectedDevice>> get detectedStream => _detectedController.stream;

  final Map<String, int> _seen = {}; // sessionToken -> latest RSSI seen

  /// This device's own session token, advertised as the BLE service UUID.
  /// UUID v4 is used directly — BLE service UUIDs are already 128-bit,
  /// exactly what a UUID is, so no separate encoding step is needed.
  String generateSessionToken() => _uuid.v4();

  /// Result of a permission request, with enough detail for the UI to tell
  /// the difference between "just say no" (can re-prompt) and "permanently
  /// denied" (Android will never show the OS dialog again — the only fix
  /// is opening Settings directly, via [openAppSettings] below).
  Future<BongPermissionResult> requestPermissions() async {
    final permissions = <String, Permission>{
      'Bluetooth advertise': Permission.bluetoothAdvertise,
      'Bluetooth scan': Permission.bluetoothScan,
      'Bluetooth connect': Permission.bluetoothConnect,
      'Location': Permission.locationWhenInUse,
    };
    final statuses = <String, PermissionStatus>{};
    for (final entry in permissions.entries) {
      try {
        statuses[entry.key] = await entry.value.request();
      } catch (e) {
        // A plugin-level failure requesting a specific permission shouldn't
        // silently hang the whole flow — surface it as denied so the UI
        // has something concrete to show instead of spinning forever.
        statuses[entry.key] = PermissionStatus.denied;
      }
    }
    final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);
    final anyPermanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    return BongPermissionResult(
      allGranted: allGranted,
      permanentlyDenied: anyPermanentlyDenied,
      statuses: statuses,
    );
  }

  /// Opens the OS app-settings screen directly — the only way forward once
  /// a permission is permanently denied, since re-requesting won't show
  /// the dialog again.
  Future<void> openSettings() => openAppSettings();

  /// Throws a plain [Exception] with a readable message on failure — the
  /// caller (bong_screen.dart) catches this and shows it inline rather
  /// than leaving the user stuck on a spinner with no explanation.
  Future<void> startAdvertising(String sessionToken) async {
    try {
      final advertiseData = AdvertiseData(
        serviceUuid: sessionToken,
        includeDeviceName: false,
      );
      await _peripheral.start(advertiseData: advertiseData);
    } catch (e) {
      throw Exception('Could not start advertising — is Bluetooth turned on? ($e)');
    }
  }

  Future<void> stopAdvertising() async {
    await _peripheral.stop();
  }

  /// Starts scanning for nearby Bong broadcasts. Every scan result the OS
  /// returns already includes an RSSI value — no custom distance math
  /// needed. Emits a running, ranked snapshot via [detectedStream]; the
  /// caller posts that snapshot to POST /bong/candidates as-is.
  Future<void> startScanning() async {
    _seen.clear();
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 60));
    } catch (e) {
      throw Exception('Could not start scanning — is Bluetooth turned on? ($e)');
    }
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final serviceUuids = r.advertisementData.serviceUuids;
        if (serviceUuids.isEmpty) continue;
        // Bong devices advertise exactly one service UUID — their session
        // token — and nothing else, so the first one IS the token.
        final token = serviceUuids.first.toString();
        _seen[token] = r.rssi;
      }
      final snapshot = _seen.entries
          .map((e) => BongDetectedDevice(e.key, e.value))
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)); // strongest signal first
      _detectedController.add(snapshot);
    });
  }

  Future<void> stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
  }

  Future<void> stopEverything() async {
    await stopScanning();
    await stopAdvertising();
  }

  void dispose() {
    _detectedController.close();
  }
}
