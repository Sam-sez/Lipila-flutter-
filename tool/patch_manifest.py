#!/usr/bin/env python3
"""
Patch android/app/src/main/AndroidManifest.xml with all permissions and
features Lipila needs. Used by both CI and local setup — run it once after
generating the android/ scaffold with `flutter create`.

Usage:
  python tool/patch_manifest.py [--path path/to/AndroidManifest.xml]

Exits non-zero if:
  - The file does not exist
  - The opening <manifest ...> tag was not found (patch would be silently skipped)
  - Any required permission/feature is missing from the output (verification step)
"""
import argparse
import re
import sys

REQUIRED_TOKENS = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.USE_BIOMETRIC',
    'android.permission.NFC',
    'android.hardware.nfc',
    'android.hardware.camera',
]

# Permissions inserted immediately after the opening <manifest ...> tag.
#
# NFC notes:
#   android.permission.NFC       — install-time permission, no runtime dialog needed.
#   android.hardware.nfc         — required=false so the APK installs on non-NFC devices.
#                                  The app checks NfcAvailability at runtime and degrades
#                                  gracefully to QR scan.
#   android.hardware.nfc.hce     — required=false for the same reason (payee HCE role).
#
# HCE service registration is handled by flutter_nfc_hce's own manifest merge
# (the plugin contributes the <service> and <meta-data> blocks automatically).
# Do NOT add them here — duplicates cause a manifest merge conflict.
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


def patch(path: str) -> None:
    try:
        with open(path) as f:
            content = f.read()
    except FileNotFoundError:
        print(f"ERROR: manifest not found at {path}", file=sys.stderr)
        sys.exit(1)

    if not re.search(r'<manifest[^>]*>', content):
        print("ERROR: <manifest ...> tag not found — patch not applied.", file=sys.stderr)
        sys.exit(1)

    patched, n = re.subn(
        r'(<manifest[^>]*>)',
        r'\1' + PERMISSIONS_BLOCK,
        content,
        count=1,
    )
    if n == 0:
        print("ERROR: re.sub matched nothing — patch not applied.", file=sys.stderr)
        sys.exit(1)

    patched = patched.replace('android:label="lipila"', 'android:label="Lipila"')

    with open(path, 'w') as f:
        f.write(patched)

    # Verification — every required token must appear in the output.
    missing = [t for t in REQUIRED_TOKENS if t not in patched]
    if missing:
        print(f"ERROR: patch verification failed — missing: {missing}", file=sys.stderr)
        sys.exit(1)

    print("--- Patched AndroidManifest.xml ---")
    print(patched)
    print("--- Verification: all required permissions present ---")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--path',
        default='android/app/src/main/AndroidManifest.xml',
        help='Path to AndroidManifest.xml (default: android/app/src/main/AndroidManifest.xml)',
    )
    args = parser.parse_args()
    patch(args.path)
