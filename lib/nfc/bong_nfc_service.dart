import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../diagnostics/app_log.dart';

// ────────────────────────────────────────────────────────────────��[...]
// BongNfcService
//
// NFC transport layer for the Bong proximity payment feature.
//
// Plugin versions this file is written against (pinned in pubspec.yaml):
//   nfc_manager       ^4.2.1  — NfcManager, NfcAvailability, NfcPollingOption
//   nfc_manager_ndef  ^1.1.0  — Ndef (separate package in 4.x; NOT re-exported
//                               by nfc_manager itself)
//
// NfcAvailability enum values in 4.x:
//   NfcAvailability.enabled      — NFC on and ready
//   NfcAvailability.disabled     — hardware present, NFC off in settings
//   NfcAvailability.unsupported  — no NFC hardware
//
// ASYMMETRIC design:
//   PAYEE  → startEmulating(token): sends token to the native BongHceService
//            (Kotlin, injected into android/ by tool/patch_manifest.py) via
//            MethodChannel 'com.lipila.bong/hce'. The native service emits the
//            token as an NDEF Text record via Android HCE.
//
//   PAYER  → startReading(onTokenRead, onError): opens an NFC reader session
//            via nfc_manager. On tap, reads the NDEF Text record and extracts
//            the UUID token.
//
// WHY NO flutter_nfc_hce PLUGIN:
//   Every Flutter HCE plugin on pub.dev breaks on current Gradle versions.
//   The Kotlin service (~130 lines) is injected directly, giving us full
//   control without third-party Gradle dependency risk.
// ────────────────────────────────────────────────────────────────�[...]

/// NFC state — own enum so callers never import nfc_manager directly.
enum NfcAvailabilityState {
  available,
  disabled,
  notSupported,
  unknown,
}

/// Permission/availability result — same shape as the old BLE result so
/// bong_screen.dart call sites are unchanged.
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

  /// MethodChannel to the native BongHceService.kt injected by patch_manifest.py.
  static const _hceChannel = MethodChannel('com.lipila.bong/hce');

  bool _isEmulating = false;
  bool _isReading = false;

  bool get isEmulating => _isEmulating;
  bool get isReading => _isReading;

  // ─── Token generation ─────────────────────────────────────────────────────

  String generateSessionToken() => _uuid.v4();

  // ─── NFC availability ─────────────────────────────────────────────────────

  /// Check NFC state using nfc_manager 4.x API.
  /// NfcManager.instance.checkAvailability() returns NfcAvailability enum.
  Future<NfcAvailabilityState> checkAvailability() async {
    AppLog.add('NFC', 'checkAvailability called');
    try {
      // nfc_manager 4.x: returns NfcAvailability enum.
      final availability = await NfcManager.instance.checkAvailability();
      AppLog.add('NFC', 'NfcManager.checkAvailability: $availability');
      switch (availability) {
        case NfcAvailability.enabled:
          return NfcAvailabilityState.available;
        case NfcAvailability.disabled:
          return NfcAvailabilityState.disabled;
        case NfcAvailability.unsupported:
          return NfcAvailabilityState.notSupported;
        default:
          return NfcAvailabilityState.unknown;
      }
    } catch (e, st) {
      AppLog.add('NFC', 'checkAvailability error: $e');
      AppLog.add('NFC', 'stack: $st');
      return NfcAvailabilityState.unknown;
    }
  }

  /// Whether HCE card emulation is available — asks the native channel.
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

  /// NFC has no runtime permission dialog — the manifest permission is granted
  /// at install time. This checks availability and returns a result the UI
  /// can act on, keeping the same call shape as the old BLE flow.
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

  /// Open OS settings — used when NFC is disabled and the user must enable it.
  Future<void> openSettings() async {
    AppLog.add('NFC', 'openSettings called');
    try {
      await openAppSettings();
    } catch (e) {
      AppLog.add('NFC', 'openSettings error: $e');
    }
  }

  // ─── PAYEE ROLE: HCE emulation ────────────────────────────────────────────

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

  // ─── PAYER ROLE: NFC reader ───────────────────────────────────────────────

  /// Enter NFC reader mode. [onTokenRead] fires once with the session token.
  /// [onError] fires for recoverable failures — scanning continues so the
  /// user can try tapping again without restarting.
  Future<void> startReading({
    required void Function(String token) onTokenRead,
    required void Function(String message) onError,
  }) async {
    AppLog.add('NFC', 'startReading called');
    try {
      // Guard: check availability before opening session.
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        const msg = 'NFC is not available or is turned off.';
        AppLog.add('NFC', 'startReading aborted: NfcAvailability=$availability');
        onError(msg);
        return;
      }

      _isReading = true;
      AppLog.add('NFC', 'startReading: opening NfcManager session');

      try {
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
              AppLog.add('NFC', 'tag read error: type=${e.runtimeType} err=$e');
              AppLog.add('NFC', 'stack: $st');
              onError('Unexpected error reading NFC tag. Try again.');
            }
          },
        );
      } catch (e, st) {
        AppLog.add('NFC', 'NfcManager session error: $e');
        AppLog.add('NFC', 'stack: $st');
        _isReading = false;
        onError('NFC session error. Please try again.');
      }

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

  // ─── NDEF token extraction ────────────────────────────────────────────────

  /// Extract the Bong session token from a discovered NFC tag.
  ///
  /// Uses nfc_manager_ndef's Ndef.from(tag) — Ndef lives in nfc_manager_ndef
  /// in nfc_manager 4.x and must be imported from there (not from nfc_manager).
  /// Returns null and logs the reason if no valid UUID token is found.
  String? _extractToken(NfcTag tag) {
    try {
      // Ndef is from nfc_manager_ndef package — handles cross-platform parsing.
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
        // NDEF Text Record: TNF=0x01, type byte 'T' (0x54)
        // Payload layout: [statusByte][langCode bytes][utf-8 text]
        final payload = record.payload;
        if (payload.isEmpty) continue;

        final statusByte = payload[0];
        final languageCodeLength = statusByte & 0x3F;
        final textStart = 1 + languageCodeLength;
        if (textStart >= payload.length) continue;

        final text = String.fromCharCodes(payload.sublist(textStart));
        AppLog.add('NFC', '_extractToken: record text="$text"');

        // Validate UUID v4 format before treating as a Bong token.
        final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        );
        if (uuidRegex.hasMatch(text)) return text;
        AppLog.add('NFC', '_extractToken: text is not a UUID — skipping');
      }

      AppLog.add('NFC', '_extractToken: no valid UUID found in any NDEF record');
      return null;
    } catch (e, st) {
      AppLog.add('NFC', '_extractToken error: $e');
      AppLog.add('NFC', 'stack: $st');
      return null;
    }
  }
}
