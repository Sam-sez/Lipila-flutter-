import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../diagnostics/app_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BongNfcService
//
// Implements the Bong proximity-payment transport layer over NFC.
// Replaces the former BLE implementation entirely.
//
// ASYMMETRIC design:
//   PAYEE  → startEmulating(token)
//            Sends the session token to the native BongHceService (Kotlin)
//            via MethodChannel. The Kotlin service emulates an NFC card using
//            Android HCE, broadcasting the token as an NDEF Text record.
//
//   PAYER  → startReading(onTokenRead, onError)
//            Puts the phone in NFC reader mode via nfc_manager. When the
//            payee's phone is tapped, the NDEF record is read, the UUID is
//            extracted, and onTokenRead is called.
//
// WHY NO flutter_nfc_hce PLUGIN:
//   Every Flutter HCE plugin on pub.dev (flutter_nfc_hce, nfc_host_card_emulation)
//   is small, unverified, and breaks on Gradle version upgrades — confirmed in CI.
//   Writing the native Kotlin service directly (< 100 lines) and wiring it via
//   MethodChannel is more reliable and keeps the build under our control.
//   The native files are injected into android/ by tool/patch_manifest.py.
//
// iOS:
//   Reader role: works (iPhone 7+, iOS 13+).
//   Emulator role: blocked by Apple — Bong stays Android-only.
// ─────────────────────────────────────────────────────────────────────────────

/// Possible NFC states — more granular than bool so the UI gives actionable messages.
enum NfcAvailabilityState {
  /// NFC on and ready.
  available,

  /// NFC hardware present but disabled in settings.
  disabled,

  /// Device has no NFC hardware.
  notSupported,

  /// State could not be determined.
  unknown,
}

/// Result of [BongNfcService.requestPermissions] — same shape as the old BLE
/// result so bong_screen.dart call sites are unchanged.
class BongNfcPermissionResult {
  final bool allGranted;
  final bool permanentlyDenied;
  final Map<String, PermissionStatus> statuses;

  BongNfcPermissionResult({
    required this.allGranted,
    required this.permanentlyDenied,
    required this.statuses,
  });

  List<String> get missing => statuses.entries
      .where((e) => !e.value.isGranted && !e.value.isLimited)
      .map((e) => e.key)
      .toList();
}

class BongNfcService {
  static const _uuid = Uuid();

  // MethodChannel to the native BongHceService (see tool/patch_manifest.py
  // which injects the Kotlin source into android/ at build time).
  static const _hceChannel = MethodChannel('com.lipila.bong/hce');

  bool _isEmulating = false;
  bool _isReading = false;

  bool get isEmulating => _isEmulating;
  bool get isReading => _isReading;

  // ─── Token generation ───────────────────────────────────────────────────

  String generateSessionToken() => _uuid.v4();

  // ─── NFC availability ───────────────────────────────────────────────────

  /// Check NFC state. Call this before showing the Bong entry point.
  Future<NfcAvailabilityState> checkAvailability() async {
    AppLog.add('NFC', 'checkAvailability called');
    try {
      final availability = await NfcManager.instance.checkAvailability();
      AppLog.add('NFC', 'NfcManager.checkAvailability: $availability');
      switch (availability) {
        case NfcAvailability.available:
          return NfcAvailabilityState.available;
        case NfcAvailability.disabled:
          return NfcAvailabilityState.disabled;
        case NfcAvailability.notSupported:
          return NfcAvailabilityState.notSupported;
      }
    } catch (e, st) {
      AppLog.add('NFC', 'checkAvailability error: $e');
      AppLog.add('NFC', 'stack: $st');
      return NfcAvailabilityState.unknown;
    }
  }

  /// Whether HCE (card emulation) is available on this device.
  /// Asks the native channel rather than guessing from the Dart side.
  Future<bool> isHceSupported() async {
    try {
      final result = await _hceChannel.invokeMethod<bool>('isHceSupported');
      final supported = result ?? false;
      AppLog.add('NFC', 'isHceSupported: $supported');
      return supported;
    } on PlatformException catch (e) {
      AppLog.add('NFC', 'isHceSupported PlatformException: ${e.message}');
      return false;
    } catch (e) {
      AppLog.add('NFC', 'isHceSupported error: $e');
      return false;
    }
  }

  // ─── Permissions ────────────────────────────────────────────────────────

  /// NFC has no runtime permission dialog on Android — the manifest permission
  /// is install-time only. This method checks NFC availability and returns
  /// a result the UI can act on, keeping the same call shape as the old BLE flow.
  Future<BongNfcPermissionResult> requestPermissions() async {
    AppLog.add('PERM', '=== NFC availability check (no runtime dialog needed) ===');
    final avail = await checkAvailability();
    final granted = avail == NfcAvailabilityState.available;
    final status = granted ? PermissionStatus.granted : PermissionStatus.denied;
    AppLog.add('PERM', 'NFC: $avail → treated as: $status');
    return BongNfcPermissionResult(
      allGranted: granted,
      permanentlyDenied: avail == NfcAvailabilityState.notSupported,
      statuses: {'NFC': status},
    );
  }

  /// Open OS settings — for when the user needs to enable NFC manually.
  Future<void> openSettings() async {
    AppLog.add('NFC', 'openSettings called');
    try {
      await openAppSettings();
    } catch (e) {
      AppLog.add('NFC', 'openSettings error: $e');
    }
  }

  // ─── PAYEE ROLE: HCE emulation ──────────────────────────────────────────

  /// Tell the native BongHceService to start emulating [sessionToken] as an
  /// NDEF Text record. The payer's phone reads this when they tap.
  Future<void> startEmulating(String sessionToken) async {
    AppLog.add('NFC', 'startEmulating token=$sessionToken');
    try {
      await _hceChannel.invokeMethod<void>('startHce', {'token': sessionToken});
      _isEmulating = true;
      AppLog.add('NFC', 'startEmulating OK');
    } on PlatformException catch (e) {
      AppLog.add('NFC',
          'startEmulating PlatformException: code=${e.code} msg=${e.message}');
      AppLog.add('NFC', 'details: ${e.details}');
      throw Exception(
        'Could not start NFC card emulation. '
        'Is NFC on? Does this device support HCE? (${e.message})',
      );
    } catch (e, st) {
      AppLog.add('NFC', 'startEmulating error: type=${e.runtimeType} err=$e');
      AppLog.add('NFC', 'stack: $st');
      throw Exception('Could not start NFC card emulation. ($e)');
    }
  }

  Future<void> stopEmulating() async {
    if (!_isEmulating) return;
    AppLog.add('NFC', 'stopEmulating called');
    try {
      await _hceChannel.invokeMethod<void>('stopHce');
      _isEmulating = false;
      AppLog.add('NFC', 'stopEmulating OK');
    } on PlatformException catch (e) {
      // Non-fatal — always called from cleanup paths.
      AppLog.add('NFC', 'stopEmulating PlatformException (non-fatal): ${e.message}');
      _isEmulating = false;
    } catch (e) {
      AppLog.add('NFC', 'stopEmulating error (non-fatal): $e');
      _isEmulating = false;
    }
  }

  // ─── PAYER ROLE: NFC reader ─────────────────────────────────────────────

  /// Enter NFC reader mode. [onTokenRead] is called once with the session token
  /// when the payee's phone is tapped. [onError] is called for recoverable
  /// failures (bad tag, no NDEF, wrong format) — scanning continues after
  /// an error so the user can try tapping again.
  Future<void> startReading({
    required void Function(String token) onTokenRead,
    required void Function(String message) onError,
  }) async {
    AppLog.add('NFC', 'startReading called');
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.available) {
        const msg = 'NFC is not available or is turned off.';
        AppLog.add('NFC', 'startReading aborted: $msg');
        onError(msg);
        return;
      }

      _isReading = true;
      AppLog.add('NFC', 'startReading: starting NfcManager session');

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          AppLog.add('NFC', 'tag discovered');
          try {
            final token = _extractToken(tag);
            if (token == null) {
              const msg =
                  'Tag found but no Bong session token — wrong device tapped?';
              AppLog.add('NFC', msg);
              onError(msg);
              return;
            }
            AppLog.add('NFC', 'token extracted: $token');
            await stopReading();
            onTokenRead(token);
          } on PlatformException catch (e) {
            AppLog.add('NFC',
                'tag read PlatformException: code=${e.code} msg=${e.message}');
            onError('Could not read NFC tag: ${e.message}');
          } catch (e, st) {
            AppLog.add('NFC',
                'tag read error: type=${e.runtimeType} err=$e');
            AppLog.add('NFC', 'stack: $st');
            onError('Unexpected error reading NFC tag. Try again.');
          }
        },
        onError: (e) async {
          AppLog.add('NFC', 'NfcManager session error: $e');
          _isReading = false;
          onError('NFC session error. Please try again.');
        },
      );
      AppLog.add('NFC', 'startReading: session open — waiting for tap');
    } on PlatformException catch (e) {
      _isReading = false;
      AppLog.add('NFC',
          'startReading PlatformException: code=${e.code} msg=${e.message}');
      throw Exception('Could not start NFC reader. Is NFC on? (${e.message})');
    } catch (e, st) {
      _isReading = false;
      AppLog.add('NFC', 'startReading error: type=${e.runtimeType} err=$e');
      AppLog.add('NFC', 'stack: $st');
      throw Exception('Could not start NFC reader. ($e)');
    }
  }

  Future<void> stopReading() async {
    if (!_isReading) return;
    AppLog.add('NFC', 'stopReading called');
    try {
      await NfcManager.instance.stopSession();
      _isReading = false;
      AppLog.add('NFC', 'stopReading OK');
    } on PlatformException catch (e) {
      AppLog.add('NFC', 'stopReading PlatformException (non-fatal): ${e.message}');
      _isReading = false;
    } catch (e) {
      AppLog.add('NFC', 'stopReading error (non-fatal): $e');
      _isReading = false;
    }
  }

  Future<void> stopEverything() async {
    AppLog.add('NFC', 'stopEverything called');
    await stopEmulating();
    await stopReading();
  }

  // ─── NDEF token extraction ──────────────────────────────────────────────

  /// Extract the Bong session token from a discovered NFC tag.
  ///
  /// Uses nfc_manager_ndef's [Ndef.from] which handles the NDEF record
  /// parsing correctly across tag types. Returns null if the tag contains
  /// no valid UUID token so the caller can surface a clear message.
  String? _extractToken(NfcTag tag) {
    try {
      final ndef = Ndef.from(tag);
      if (ndef == null) {
        AppLog.add('NFC', '_extractToken: tag is not NDEF-compatible');
        return null;
      }

      final message = ndef.cachedMessage;
      if (message == null || message.records.isEmpty) {
        AppLog.add('NFC', '_extractToken: no cached NDEF message');
        return null;
      }

      for (final record in message.records) {
        // NDEF Text Record TNF=0x01, type=0x54 ('T')
        // Payload: [statusByte][languageCode][text]
        final payload = record.payload;
        if (payload.isEmpty) continue;

        final statusByte = payload[0];
        final languageCodeLength = statusByte & 0x3F;
        final textStart = 1 + languageCodeLength;

        if (textStart >= payload.length) continue;

        final text = String.fromCharCodes(payload.sublist(textStart));
        AppLog.add('NFC', '_extractToken: record text="$text"');

        // Validate UUID format before treating as a Bong token.
        final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        );
        if (uuidRegex.hasMatch(text)) return text;
        AppLog.add('NFC', '_extractToken: not a UUID — skipping');
      }

      AppLog.add('NFC', '_extractToken: no valid UUID token found');
      return null;
    } catch (e, st) {
      AppLog.add('NFC', '_extractToken error: $e');
      AppLog.add('NFC', 'stack: $st');
      return null;
    }
  }
}
