import 'dart:async';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:flutter_nfc_hce/flutter_nfc_hce.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../diagnostics/app_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BongNfcService
//
// Replaces BongBleService entirely. Implements the same Bong protocol
// (announce → candidates → reveal → pay) but over NFC instead of BLE.
//
// ASYMMETRIC design — one phone per role per session:
//   PAYEE  → startEmulating(token) — phone acts as an NFC card (HCE).
//            The session token is written as a plain-text NDEF record.
//   PAYER  → startReading(onToken) — phone polls for an NFC tag.
//            When it reads a token it calls onToken and stops.
//
// Why asymmetric:
//   Running both HCE and reader on the same device simultaneously causes radio
//   contention and unreliable reads. The physical tap is the coordination step
//   that replaces BLE's "scan for 60 s" window.
//
// Device support:
//   NFC hardware is required for both roles. Devices without NFC fall back to
//   QR scan (already implemented in scan_screen.dart). isNfcAvailable() lets
//   the UI gate access before showing the Bong option.
//
// iOS:
//   Reader role: supported (iPhone 7+, iOS 13+).
//   Emulator role: NOT supported — Apple locks HCE to Apple Pay.
//   Since Bong is Android-only by design this is acceptable.
// ─────────────────────────────────────────────────────────────────────────────

/// Result returned by [BongNfcService.requestPermissions].
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

/// Possible NFC availability states — more granular than a plain bool so the
/// UI can give the user an actionable message for each case.
enum NfcAvailability {
  /// NFC hardware present and switched on — ready to use.
  available,

  /// NFC hardware present but turned off in Android settings.
  disabled,

  /// Device has no NFC hardware at all.
  notSupported,

  /// Could not determine state (plugin error, unexpected platform).
  unknown,
}

class BongNfcService {
  static const _uuid = Uuid();
  final FlutterNfcHce _hce = FlutterNfcHce();

  bool _isEmulating = false;
  bool _isReading = false;

  // ─── Public state flags ────────────────────────────────────────────────
  bool get isEmulating => _isEmulating;
  bool get isReading => _isReading;

  // ─── Session token ─────────────────────────────────────────────────────
  String generateSessionToken() => _uuid.v4();

  // ─── NFC availability ──────────────────────────────────────────────────

  /// Check whether NFC is available and switched on.
  /// Always call this before showing the Bong entry point in the UI.
  Future<NfcAvailability> checkAvailability() async {
    AppLog.add('NFC', 'checkAvailability called');
    try {
      final available = await NfcManager.instance.isAvailable();
      if (available) {
        AppLog.add('NFC', 'availability: available');
        return NfcAvailability.available;
      }
      // isAvailable() returns false for both "no hardware" and "hardware off".
      // Try the HCE plugin's isNfcEnabled to distinguish the two.
      try {
        final enabled = await _hce.isNfcEnabled();
        if (enabled == false) {
          AppLog.add('NFC', 'availability: disabled (NFC off in settings)');
          return NfcAvailability.disabled;
        }
      } catch (_) {
        // HCE plugin not available or threw — fall through to notSupported.
      }
      AppLog.add('NFC', 'availability: notSupported');
      return NfcAvailability.notSupported;
    } catch (e, st) {
      AppLog.add('NFC', 'checkAvailability error: $e');
      AppLog.add('NFC', 'stack: $st');
      return NfcAvailability.unknown;
    }
  }

  /// Whether this device supports HCE (card emulation — needed for payee role).
  Future<bool> isHceSupported() async {
    try {
      final supported = await _hce.isNfcHceSupported();
      AppLog.add('NFC', 'HCE supported: $supported');
      return supported ?? false;
    } catch (e) {
      AppLog.add('NFC', 'isHceSupported error: $e');
      return false;
    }
  }

  // ─── Permissions ───────────────────────────────────────────────────────

  /// NFC itself does not require a runtime permission on Android — the
  /// <uses-permission android:name="android.permission.NFC"/> in the manifest
  /// is sufficient and is granted at install time. This method exists to:
  ///   1. Log the current NFC availability state (useful for diagnostics).
  ///   2. Keep the same call-site shape as the old BLE permission flow so
  ///      bong_screen.dart changes are minimal.
  Future<BongNfcPermissionResult> requestPermissions() async {
    AppLog.add('PERM', '=== NFC permission check ===');
    // NFC has no runtime permission — check availability instead.
    final avail = await checkAvailability();
    final granted = avail == NfcAvailability.available;
    final status =
        granted ? PermissionStatus.granted : PermissionStatus.denied;
    final statuses = {'NFC': status};

    AppLog.add('PERM', 'NFC availability: $avail  treated as: $status');

    return BongNfcPermissionResult(
      allGranted: granted,
      permanentlyDenied: avail == NfcAvailability.notSupported,
      statuses: statuses,
    );
  }

  /// Opens OS app settings — used when user must enable NFC manually.
  Future<void> openSettings() async {
    AppLog.add('NFC', 'openSettings called');
    try {
      await openAppSettings();
    } catch (e) {
      AppLog.add('NFC', 'openSettings error: $e');
    }
  }

  // ─── PAYEE ROLE: HCE emulation ─────────────────────────────────────────

  /// Start advertising [sessionToken] as an NDEF text record via HCE.
  /// The payer's phone reads this token when they tap.
  ///
  /// [persistMessage] = false ensures the HCE advertisement stops cleanly
  /// when [stopEmulating] is called and does not survive app restarts.
  Future<void> startEmulating(String sessionToken) async {
    AppLog.add('NFC', 'startEmulating token=$sessionToken');
    try {
      final result = await _hce.startNfcHce(
        sessionToken,
        mimeType: 'text/plain',
        persistMessage: false,
      );
      _isEmulating = true;
      AppLog.add('NFC', 'startEmulating OK result=$result');
    } on PlatformException catch (e) {
      AppLog.add('NFC', 'startEmulating PlatformException: code=${e.code} msg=${e.message}');
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
      await _hce.stopNfcHce();
      _isEmulating = false;
      AppLog.add('NFC', 'stopEmulating OK');
    } on PlatformException catch (e) {
      // Log but don't rethrow — stopEmulating is always called in cleanup
      // paths where throwing would leave state inconsistent.
      AppLog.add('NFC', 'stopEmulating PlatformException (non-fatal): ${e.message}');
      _isEmulating = false;
    } catch (e) {
      AppLog.add('NFC', 'stopEmulating error (non-fatal): $e');
      _isEmulating = false;
    }
  }

  // ─── PAYER ROLE: NFC reader ─────────────────────────────────────────────

  /// Begin scanning for an NFC tap. When a tag is read, [onTokenRead] is
  /// called with the session token and scanning stops automatically.
  ///
  /// [onError] is called for any read failure (bad tag format, unsupported
  /// tag type, OS-level error). Scanning continues after an error — the
  /// user can try tapping again.
  Future<void> startReading({
    required void Function(String token) onTokenRead,
    required void Function(String message) onError,
  }) async {
    AppLog.add('NFC', 'startReading called');
    try {
      final available = await NfcManager.instance.isAvailable();
      if (!available) {
        const msg = 'NFC is not available on this device or is turned off.';
        AppLog.add('NFC', 'startReading aborted: $msg');
        onError(msg);
        return;
      }

      _isReading = true;
      AppLog.add('NFC', 'startReading: NfcManager.instance.startSession');

      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          AppLog.add('NFC', 'tag discovered: techList=${tag.data.keys.toList()}');
          try {
            final token = _extractTokenFromTag(tag);
            if (token == null) {
              const msg =
                  'Tag found but no Bong session token in it — wrong device tapped?';
              AppLog.add('NFC', msg);
              onError(msg);
              return;
            }
            AppLog.add('NFC', 'token extracted: $token');
            // Stop before calling onTokenRead so we don't keep the session
            // open while the payment flow runs.
            await stopReading();
            onTokenRead(token);
          } on PlatformException catch (e) {
            AppLog.add('NFC', 'tag read PlatformException: code=${e.code} msg=${e.message}');
            onError('Could not read NFC tag: ${e.message}');
          } catch (e, st) {
            AppLog.add('NFC', 'tag read error: type=${e.runtimeType} err=$e');
            AppLog.add('NFC', 'stack: $st');
            onError('Unexpected error reading NFC tag.');
          }
        },
        onError: (e) async {
          // onError fires for session-level failures (e.g. NFC turned off
          // mid-session), not per-tag errors — those go to onDiscovered above.
          AppLog.add('NFC', 'NfcManager session error: $e');
          _isReading = false;
          onError('NFC session error. Please try again.');
        },
      );

      AppLog.add('NFC', 'startReading: session started OK — waiting for tap');
    } on PlatformException catch (e) {
      _isReading = false;
      AppLog.add('NFC', 'startReading PlatformException: code=${e.code} msg=${e.message}');
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

  // ─── Stop everything ───────────────────────────────────────────────────

  Future<void> stopEverything() async {
    AppLog.add('NFC', 'stopEverything called');
    await stopEmulating();
    await stopReading();
  }

  // ─── Internal ──────────────────────────────────────────────────────────

  /// Extract the Bong session token from an NFC tag.
  ///
  /// The payee's phone emits a plain-text NDEF record containing only the
  /// UUID token. We look for the first NDEF text record and return its text.
  /// Returns null if no usable token is found so the caller can surface a
  /// clear "wrong device" message rather than crashing.
  String? _extractTokenFromTag(NfcTag tag) {
    try {
      // nfc_manager represents NDEF data under the 'ndef' key.
      final ndefData = tag.data['ndef'];
      if (ndefData == null) {
        AppLog.add('NFC', '_extractToken: no ndef data in tag');
        return null;
      }

      final cachedMessage = ndefData['cachedMessage'];
      if (cachedMessage == null) {
        AppLog.add('NFC', '_extractToken: no cachedMessage');
        return null;
      }

      final records = cachedMessage['records'] as List?;
      if (records == null || records.isEmpty) {
        AppLog.add('NFC', '_extractToken: empty records list');
        return null;
      }

      for (final record in records) {
        final payload = record['payload'];
        if (payload == null) continue;

        // NDEF Text Record payload: first byte is status byte (language code
        // length), followed by the language code, then the actual text.
        // We strip the header and return the text portion.
        List<int> bytes;
        if (payload is List) {
          bytes = List<int>.from(payload);
        } else {
          AppLog.add('NFC', '_extractToken: unexpected payload type ${payload.runtimeType}');
          continue;
        }

        if (bytes.isEmpty) continue;

        final statusByte = bytes[0];
        final languageCodeLength = statusByte & 0x3F;
        final textStart = 1 + languageCodeLength;

        if (textStart >= bytes.length) continue;

        final text = String.fromCharCodes(bytes.sublist(textStart));
        AppLog.add('NFC', '_extractToken: extracted text="$text"');

        // Validate it looks like a UUID before treating it as a token.
        final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        );
        if (uuidRegex.hasMatch(text)) {
          return text;
        }
        AppLog.add('NFC', '_extractToken: text does not look like a UUID — skipping');
      }

      AppLog.add('NFC', '_extractToken: no valid UUID token found in any record');
      return null;
    } catch (e, st) {
      AppLog.add('NFC', '_extractToken error: $e');
      AppLog.add('NFC', 'stack: $st');
      return null;
    }
  }
}
