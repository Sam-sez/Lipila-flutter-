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

  /// Requests every runtime permission Bong needs. Call this BEFORE
  /// start() with an explanation shown first — don't fire OS prompts cold.
  /// Android 12+ needs the three BLUETOOTH_* permissions; older Android
  /// gates BLE scan results behind location permission (a long-standing
  /// platform quirk, not a Lipila design choice).
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> startAdvertising(String sessionToken) async {
    final advertiseData = AdvertiseData(
      serviceUuid: sessionToken,
      includeDeviceName: false,
    );
    await _peripheral.start(advertiseData: advertiseData);
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
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 60));
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
