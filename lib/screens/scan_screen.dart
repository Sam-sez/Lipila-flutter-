import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../state/auth_provider.dart';
import '../api/qr_api.dart';
import '../theme/lipila_theme.dart';
import '../widgets/pay_confirm_sheet.dart';

enum _CameraState { checking, granted, denied, permanentlyDenied }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _qrApi = QrApi();
  MobileScannerController? _controller;
  bool _handledOnce = false;
  String? _error;
  _CameraState _cameraState = _CameraState.checking;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  /// Declaring CAMERA in the manifest isn't enough — Android requires the
  /// runtime permission to actually be granted before the camera opens.
  /// Skipping this check is what caused the "getClass() on a null object
  /// reference" crash: the camera plugin tried to initialize without a
  /// granted permission and failed in a way that surfaces as a confusing
  /// native error instead of a clean "permission denied" message.
  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      setState(() {
        _cameraState = _CameraState.granted;
        _controller = MobileScannerController();
      });
    } else if (status.isPermanentlyDenied) {
      setState(() => _cameraState = _CameraState.permanentlyDenied);
    } else {
      setState(() => _cameraState = _CameraState.denied);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledOnce || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null) return;

    final match = RegExp(r'lipila://(static|dynamic)/([\w-]+)').firstMatch(value);
    if (match == null) {
      setState(() => _error = "That doesn't look like a Lipila QR code.");
      return;
    }
    _handledOnce = true;
    try {
      await _controller?.stop();
    } catch (_) {
      // Stopping an already-stopped/erroring controller shouldn't block
      // resolving the code we already captured.
    }

    final kind = match.group(1)!;
    final token = match.group(2)!;
    await _resolve(kind, token);
  }

  Future<void> _resolve(String kind, String token) async {
    final payerId = context.read<AuthProvider>().user!.id;
    try {
      if (kind == 'static') {
        final identity = await _qrApi.resolveStatic(token);
        if (!mounted) return;
        await showPayConfirmSheet(context: context, payerId: payerId, payee: identity, method: 'static_qr');
      } else {
        final resolved = await _qrApi.resolveDynamic(token);
        if (!mounted) return;
        await showPayConfirmSheet(
          context: context, payerId: payerId, payee: resolved.payee,
          lockedAmount: resolved.amount, method: 'dynamic_qr',
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not resolve this QR code — it may have expired.');
    } finally {
      _handledOnce = false;
      try {
        await _controller?.start();
      } catch (_) {
        // If the camera can't restart, the errorBuilder below will catch
        // it and show a retry option rather than leaving a dead screen.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to pay')),
      body: Column(
        children: [
          Expanded(child: _buildCameraArea()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: LipilaColors.danger)),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Point your camera at a Static or Dynamic Lipila QR code.', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    switch (_cameraState) {
      case _CameraState.checking:
        return const Center(child: CircularProgressIndicator());
      case _CameraState.denied:
        return _permissionMessage(
          'Camera access is needed to scan QR codes.',
          onRetry: _checkCameraPermission,
        );
      case _CameraState.permanentlyDenied:
        return _permissionMessage(
          "Camera access was denied and won't be asked again automatically — "
          "enable it in Settings.",
          onOpenSettings: openAppSettings,
        );
      case _CameraState.granted:
        return MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          // Without this, a native camera failure shows mobile_scanner's
          // own raw error screen (the "genericError" crash reported) —
          // this replaces it with a Lipila-styled retry instead.
          errorBuilder: (context, error, child) => _cameraErrorMessage(error),
        );
    }
  }

  Widget _permissionMessage(String message, {VoidCallback? onRetry, VoidCallback? onOpenSettings}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (onRetry != null) OutlinedButton(onPressed: onRetry, child: const Text('Grant camera access')),
          if (onOpenSettings != null) OutlinedButton(onPressed: onOpenSettings, child: const Text('Open app settings')),
        ]),
      ),
    );
  }

  Widget _cameraErrorMessage(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: LipilaColors.danger),
          const SizedBox(height: 12),
          const Text('The camera failed to start.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(error.errorCode.name, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _checkCameraPermission, child: const Text('Retry')),
        ]),
      ),
    );
  }
}
