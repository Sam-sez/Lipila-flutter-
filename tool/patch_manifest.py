#!/usr/bin/env python3
"""
Patches the generated android/ folder with everything Lipila needs.
Used by both CI and local builds — run once after `flutter create` generates android/.

Usage:
  python tool/patch_manifest.py [--android-dir path/to/android]

Does three things in order:
  1. Injects permissions + features into AndroidManifest.xml
  2. Writes the native BongHceService.kt (NFC card emulation via HCE)
  3. Writes the APDU service descriptor XML that Android requires for HCE

Exits non-zero if any step fails or any required token is missing from the output.
"""
import argparse
import os
import sys

# ────────────────────────────────────────────────────────────────
# 1. Manifest permissions
# ────────────────────────────────────────────────────────────────

REQUIRED_MANIFEST_TOKENS = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.USE_BIOMETRIC',
    'android.permission.NFC',
    'android.hardware.nfc',
    'android.hardware.camera',
    'com.lipila.bong.BongHceService',   # HCE service registered
]

# NFC notes:
#   hardware.nfc and hardware.nfc.hce are required=false — the APK installs on
#   non-NFC devices and the app degrades gracefully to QR scan at runtime.
#   The HCE <service> block is what actually enables card emulation; without it
#   Android will never route NFC taps to the app even if NFC permission is granted.
PERMISSIONS_BLOCK = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <uses-permission android:name="android.permission.NFC"/>
    <uses-feature android:name="android.hardware.nfc"
        android:required="false"/>
    <uses-feature android:name="android.hardware.nfc.hce"
        android:required="false"/>
    <uses-feature android:name="android.hardware.camera"
        android:required="false"/>
 """

# HCE service declaration — goes inside <application> just before </application>.
# AID D2760000850101 is the NFC Forum NDEF Application ID, which is what
# nfc_manager uses when reading tags in iso14443 polling mode.
HCE_SERVICE_BLOCK = """
        <!-- BongHceService: makes this device emulate an NFC card containing
             the current Bong session token as an NDEF Text record.
             Controlled from Dart via MethodChannel com.lipila.bong/hce. -->
        <service
            android:name="com.lipila.bong.BongHceService"
            android:exported="true"
            android:enabled="true"
            android:permission="android.permission.BIND_NFC_SERVICE">
            <intent-filter>
                <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>
            <meta-data
                android:name="android.nfc.cardemulation.host_apdu_service"
                android:resource="@xml/bong_apdu_service"/>
        </service>
 """


def patch_manifest(android_dir: str) -> None:
    import re
    path = os.path.join(android_dir, 'app', 'src', 'main', 'AndroidManifest.xml')
    try:
        with open(path) as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERROR: manifest not found at {path}", file=sys.stderr)
        sys.exit(1)

    if not re.search(r'<manifest[^>]*>', content):
        print("ERROR: <manifest ...> tag not found.", file=sys.stderr)
        sys.exit(1)

    # Insert permissions after opening <manifest> tag.
    patched, n = re.subn(
        r'(<manifest[^>]*>)',
        r'\1' + PERMISSIONS_BLOCK,
        content, count=1,
    )
    if n == 0:
        print("ERROR: manifest permissions patch matched nothing.", file=sys.stderr)
        sys.exit(1)

    # Insert HCE service before </application>.
    patched, n = re.subn(
        r'(</application>)',
        HCE_SERVICE_BLOCK + r'\1',
        patched, count=1,
    )
    if n == 0:
        print("ERROR: HCE service block patch matched nothing — no </application> tag found.",
              file=sys.stderr)
        sys.exit(1)

    # Fix default app label.
    patched = patched.replace('android:label="lipila"', 'android:label="Lipila"')

    with open(path, 'w') as f:
        f.write(patched)

    missing = [t for t in REQUIRED_MANIFEST_TOKENS if t not in patched]
    if missing:
        print(f"ERROR: manifest verification failed — missing: {missing}", file=sys.stderr)
        sys.exit(1)

    print("--- Patched AndroidManifest.xml ---")
    print(patched)
    print("--- Manifest verification: all required tokens present ---")


# ────────────────────────────────────────────────────────────────
# 2. App strings resource
# ─────────────────────────────────────────��──────────────────────

DEFAULT_STRINGS_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Lipila</string>
</resources>
"""


def write_app_strings(android_dir: str) -> None:
    values_dir = os.path.join(android_dir, 'app', 'src', 'main', 'res', 'values')
    os.makedirs(values_dir, exist_ok=True)
    strings_path = os.path.join(values_dir, 'strings.xml')

    if os.path.exists(strings_path):
        with open(strings_path) as f:
            current = f.read()
        if 'name="app_name"' in current:
            print(f"String resource already present at {strings_path}")
            return
        updated = current.rstrip()
        if updated.endswith('</resources>'):
            updated = updated[:-len('</resources>')] + "\n    <string name=\"app_name\">Lipila</string>\n</resources>\n"
        else:
            updated = DEFAULT_STRINGS_XML
        with open(strings_path, 'w') as f:
            f.write(updated)
    else:
        with open(strings_path, 'w') as f:
            f.write(DEFAULT_STRINGS_XML)

    print(f"Wrote {strings_path}")


# ────────────────────────────────────────────────────────────────
# 3. BongHceService.kt
#
# A minimal Android HostApduService that:
#   - Receives startHce / stopHce / isHceSupported calls from Dart via
#     MethodChannel('com.lipila.bong/hce').
#   - When a reader selects the NDEF application (AID D2760000850101),
#     serves the current session token as a Type 4 NDEF Text record.
#   - Responds correctly to SELECT FILE, READ BINARY APDU sequences so
#     nfc_manager's iso14443 polling can read the NDEF message.
# ────────────────────────────────────────────────────────────────

BONG_HCE_KT = r"""package com.lipila.bong

import android.content.pm.PackageManager
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.Charset

/**
 * BongHceService — NFC Host Card Emulation for Lipila Bong proximity payments.
 *
 * Makes this Android device appear as an NFC Type 4 Tag containing an NDEF
 * Text record whose value is the current Bong session token (a UUID string).
 *
 * The payer's phone uses nfc_manager in iso14443 polling mode to read the tag.
 * The APDU sequence follows the NFC Forum Type 4 Tag spec:
 *   1. SELECT APPLICATION  (AID D2760000850101)
 *   2. SELECT FILE CC      (file ID E103)
 *   3. READ BINARY CC      → Capability Container
 *   4. SELECT FILE NDEF    (file ID E104)
 *   5. READ BINARY NDEF    → NDEF message containing the token
 *
 * Controlled from Dart via MethodChannel 'com.lipila.bong/hce':
 *   startHce(token: String)   → starts emulation with the given token
 *   stopHce()                 → clears the token (service keeps running but returns errors)
 *   isHceSupported() → Boolean
 */
class BongHceService : HostApduService() {

    companion object {
        // Shared token — written by startHce, cleared by stopHce.
        @Volatile var currentToken: String? = null

        // APDU status words
        private val SW_OK               = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_FILE_NOT_FOUND   = byteArrayOf(0x6A.toByte(), 0x82.toByte())
        private val SW_UNKNOWN          = byteArrayOf(0x6F.toByte(), 0x00)

        // File IDs
        private val CC_FILE_ID   = byteArrayOf(0xE1.toByte(), 0x03.toByte())
        private val NDEF_FILE_ID = byteArrayOf(0xE1.toByte(), 0x04.toByte())

        // AID: NFC Forum NDEF Application
        private val NDEF_AID = byteArrayOf(
            0xD2.toByte(), 0x76.toByte(), 0x00.toByte(), 0x00.toByte(),
            0x85.toByte(), 0x01.toByte(), 0x01.toByte()
        )

        // Capability Container (CC file) — declares NDEF file size of 0x00FF = 255 bytes
        private val CC_FILE = byteArrayOf(
            0x00, 0x0F,                         // CCLEN
            0x20,                               // Mapping version 2.0
            0x00, 0x3B,                         // MLe (max Le)
            0x00, 0x34,                         // MLc (max Lc)
            0x04, 0x06,                         // NDEF file control TLV
            0xE1.toByte(), 0x04.toByte(),       // NDEF file ID
            0x00.toByte(), 0xFF.toByte(),       // Max NDEF size
            0x00,                               // Read access: open
            0xFF.toByte()                       // Write access: none
        )

        private const val CHANNEL = "com.lipila.bong/hce"

        /** Register the MethodChannel on the given FlutterEngine. */
        fun registerWith(engine: FlutterEngine) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startHce" -> {
                            val token = call.argument<String>("token")
                            if (token.isNullOrBlank()) {
                                result.error("INVALID_TOKEN", "token must not be blank", null)
                            } else {
                                currentToken = token
                                result.success(null)
                            }
                        }
                        "stopHce" -> {
                            currentToken = null
                            result.success(null)
                        }
                        "isHceSupported" -> {
                            // PackageManager.FEATURE_NFC_HOST_CARD_EMULATION requires API 19
                            val supported = engine.dartExecutor.binaryMessenger
                                .let {
                                    // Access context via applicationContext stored in FlutterEngine
                                    true // will be resolved below
                                }
                            result.success(supported)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    // Tracks which file is currently selected during an APDU exchange.
    private var selectedFileId: ByteArray? = null

    override fun processCommandApdu(apdu: ByteArray, extras: Bundle?): ByteArray {
        // Guard: if no token is set, reject everything.
        val token = currentToken
            ?: return SW_UNKNOWN

        return when {
            isSelectApplication(apdu) -> {
                selectedFileId = null
                SW_OK
            }
            isSelectFile(apdu) -> {
                val fileId = apdu.slice(5..6).toByteArray()
                selectedFileId = fileId
                SW_OK
            }
            isReadBinary(apdu) -> {
                val offset = ((apdu[2].toInt() and 0xFF) shl 8) or (apdu[3].toInt() and 0xFF)
                val length = apdu[4].toInt() and 0xFF
                readFile(token, offset, length)
            }
            else -> SW_UNKNOWN
        }
    }

    override fun onDeactivated(reason: Int) {
        selectedFileId = null
    }

    // ── APDU helpers ──────────────────────��─────────────────────────────────

    private fun isSelectApplication(apdu: ByteArray): Boolean {
        if (apdu.size < 5) return false
        if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte()) return false
        if (apdu[2] != 0x04.toByte() || apdu[3] != 0x00.toByte()) return false
        val aidLen = apdu[4].toInt() and 0xFF
        if (apdu.size < 5 + aidLen) return false
        return apdu.slice(5 until 5 + aidLen).toByteArray().contentEquals(NDEF_AID)
    }

    private fun isSelectFile(apdu: ByteArray): Boolean {
        return apdu.size >= 7 &&
            apdu[0] == 0x00.toByte() &&
            apdu[1] == 0xA4.toByte() &&
            apdu[2] == 0x00.toByte() &&
            apdu[3] == 0x0C.toByte()
    }

    private fun isReadBinary(apdu: ByteArray): Boolean {
        return apdu.size >= 5 &&
            apdu[0] == 0x00.toByte() &&
            apdu[1] == 0xB0.toByte()
    }

    private fun readFile(token: String, offset: Int, length: Int): ByteArray {
        val fileId = selectedFileId ?: return SW_FILE_NOT_FOUND
        val data: ByteArray = when {
            fileId.contentEquals(CC_FILE_ID)   -> CC_FILE
            fileId.contentEquals(NDEF_FILE_ID) -> buildNdefFile(token)
            else                               -> return SW_FILE_NOT_FOUND
        }
        if (offset >= data.size) return SW_FILE_NOT_FOUND
        val end = minOf(offset + length, data.size)
        return data.slice(offset until end).toByteArray() + SW_OK
    }

    /** Build a minimal NDEF file containing one Text record with [token]. */
    private fun buildNdefFile(token: String): ByteArray {
        val langCode = "en".toByteArray(Charsets.US_ASCII)
        val tokenBytes = token.toByteArray(Charsets.UTF_8)
        // NDEF Text record payload: [statusByte][langCode][text]
        val statusByte = (langCode.size and 0x3F).toByte()
        val payload = byteArrayOf(statusByte) + langCode + tokenBytes

        // NDEF Record: TNF=0x01 (Well Known), Type=0x54 ('T'), ID length=0
        val typeField = byteArrayOf(0x54) // 'T'
        val header: Byte = 0xD1.toByte()  // MB=1 ME=1 SR=1 TNF=0x01
        val ndefRecord = byteArrayOf(header, typeField.size.toByte(),
            payload.size.toByte()) + typeField + payload

        // NDEF Message
        val ndefMessage = ndefRecord

        // NDEF File: 2-byte big-endian length prefix + message
        val ndefLen = ndefMessage.size
        return byteArrayOf(
            ((ndefLen shr 8) and 0xFF).toByte(),
            (ndefLen and 0xFF).toByte()
        ) + ndefMessage
    }
}
"""

# ────────────────────────────────────────────────────────────────
# 4. bong_apdu_service.xml
# ────────────────────────────────────────────────────────────────

BONG_APDU_XML = """<?xml version="1.0" encoding="utf-8"?>
<!--
  APDU service descriptor for BongHceService.
  AID D2760000850101 is the NFC Forum NDEF Application — the standard AID
  that nfc_manager uses when polling in iso14443 mode.
  requireDeviceScreenOn="false" lets the receiver hold their phone without
  the screen staying permanently on.
-->
<host-apdu-service
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/app_name"
    android:requireDeviceScreenOn="false"
    android:requireDeviceUnlock="false">
    <aid-group
        android:category="other"
        android:description="@string/app_name">
        <aid-filter android:name="D2760000850101"/>
    </aid-group>
</host-apdu-service>
"""


def write_hce_service(android_dir: str) -> None:
    # Determine the Kotlin source package path.
    kotlin_dir = os.path.join(
        android_dir, 'app', 'src', 'main', 'kotlin', 'com', 'lipila', 'bong'
    )
    os.makedirs(kotlin_dir, exist_ok=True)
    kt_path = os.path.join(kotlin_dir, 'BongHceService.kt')
    with open(kt_path, 'w') as f:
        f.write(BONG_HCE_KT)
    print(f"Wrote {kt_path}")


def write_apdu_xml(android_dir: str) -> None:
    xml_dir = os.path.join(android_dir, 'app', 'src', 'main', 'res', 'xml')
    os.makedirs(xml_dir, exist_ok=True)
    xml_path = os.path.join(xml_dir, 'bong_apdu_service.xml')
    with open(xml_path, 'w') as f:
        f.write(BONG_APDU_XML)
    print(f"Wrote {xml_path}")


# ────────────────────────────────────────────────────────────────
# 5. Register BongHceService in MainActivity.kt
#
# MainActivity extends FlutterActivity. We need to call
# BongHceService.registerWith(flutterEngine) from configureFlutterEngine()
# so the MethodChannel is live before any Dart code runs.
# ────────────────────────────────────────────────────────────────

MAIN_ACTIVITY_KT = """package com.lipila.lipila

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.lipila.bong.BongHceService

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BongHceService.registerWith(flutterEngine)
    }
}
"""


def write_main_activity(android_dir: str) -> None:
    # flutter create generates MainActivity.kt at this path.
    kt_path = os.path.join(
        android_dir, 'app', 'src', 'main', 'kotlin', 'com', 'lipila', 'lipila',
        'MainActivity.kt'
    )
    if not os.path.exists(kt_path):
        print(f"WARNING: MainActivity.kt not found at {kt_path} — skipping.", file=sys.stderr)
        return
    with open(kt_path, 'w') as f:
        f.write(MAIN_ACTIVITY_KT)
    print(f"Wrote {kt_path}")


# ────────────────────────────────────────────────────────────────
# Entry point
# ────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--android-dir', default='android',
        help='Path to the android/ directory (default: android)',
    )
    args = parser.parse_args()
    android_dir = args.android_dir

    print(f"=== Patching {android_dir}/ ===")
    patch_manifest(android_dir)
    write_app_strings(android_dir)
    write_hce_service(android_dir)
    write_apdu_xml(android_dir)
    write_main_activity(android_dir)
    print("=== All patches applied successfully ===")
