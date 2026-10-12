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
  - Any required permission/feature is missing from the output file (verification step)
"""
import argparse
import re
import sys

REQUIRED_TOKENS = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.USE_BIOMETRIC',
    'android.permission.BLUETOOTH_ADVERTISE',
    'android.permission.BLUETOOTH_SCAN',
    'android.permission.BLUETOOTH_CONNECT',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.hardware.bluetooth_le',
    'android.hardware.camera',
]

# Permissions inserted immediately after the opening <manifest ...> tag.
# Notes on each declaration:
#   BLUETOOTH_ADVERTISE — usesPermissionFlags="neverForLocation" is
#     technically only meaningful on BLUETOOTH_SCAN but is harmless here;
#     left as-is pending deliberate cleanup in a later iteration.
#   ACCESS_FINE_LOCATION maxSdkVersion="30" — on Android 12+ (SDK 31+) the
#     BLE scan uses neverForLocation so no location permission is needed.
#     On Android <= 11 it IS needed and will be requested by the code.
#   BLUETOOTH / BLUETOOTH_ADMIN (maxSdkVersion="30") are NOT injected here
#     because flutter_ble_peripheral contributes them automatically via its
#     own manifest merge, as documented in the plugin's README. Verify with
#     `aapt2 dump permissions` if you suspect they're missing.
PERMISSIONS_BLOCK = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"
        android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30"/>
    <uses-feature android:name="android.hardware.bluetooth_le"
        android:required="true"/>
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

    # Fail loudly if the tag we're anchoring on isn't there.
    if not re.search(r'<manifest[^>]*>', content):
        print("ERROR: <manifest ...> tag not found — patch not applied.", file=sys.stderr)
        sys.exit(1)

    # Insert right after the opening <manifest ...> tag (count=1 = first match only).
    patched, n = re.subn(
        r'(<manifest[^>]*>)',
        r'\1' + PERMISSIONS_BLOCK,
        content,
        count=1,
    )
    if n == 0:
        print("ERROR: re.sub matched nothing — patch not applied.", file=sys.stderr)
        sys.exit(1)

    # Fix the default app label.
    patched = patched.replace('android:label="lipila"', 'android:label="Lipila"')

    with open(path, 'w') as f:
        f.write(patched)

    # Verification: every required token must appear in the output.
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
