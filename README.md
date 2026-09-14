# Lipila (Flutter / Android)

Native Android client for Lipila, with **real BLE for Bong** — the
proximity-pay feature the web version could only simulate.

## How this was built

This repo has no `android/` folder committed. Every push triggers
`.github/workflows/build_apk.yml`, which:

1. Runs `flutter create` fresh to generate a version-correct Android
   Gradle scaffold (rather than a hand-maintained one that could go stale).
2. Patches in the BLE/camera/biometric permissions Bong and Scan need.
3. Runs `flutter pub get` and `flutter build apk --release`.
4. Uploads the resulting APK as a downloadable workflow artifact.

**This code was written without a local Flutter/Android toolchain** — no
emulator, no local compile, no local test run. GitHub's runners are the
only thing that has ever actually compiled it. Check the Actions tab for
the real build status before assuming anything here works.

## Backend

This app is a client only — it talks to the same production API as the
web version: `https://lipila.vercel.app/api`. See
[`Sam-sez/Lipila`](https://github.com/Sam-sez/Lipila) for the backend
source (FastAPI, deployed on Vercel + Neon + Upstash). No backend changes
are needed for this app to work.

## Bong — real BLE, with a real limitation

Bong uses two plugins together (`flutter_blue_plus` for scanning,
`flutter_ble_peripheral` for advertising) since no single Flutter BLE
package reliably does both roles. **This can only be tested on two real
physical Android devices** — no emulator supports BLE peripheral mode.
See `lib/ble/bong_ble_service.dart` for the protocol and known risk areas.

Android only, by design — iOS's BLE peripheral (advertising) mode is
significantly more restricted, and supporting it well was out of scope
for this build.

## Getting the APK

Once a build succeeds (check the **Actions** tab), open that run and
download the `lipila-release-apk` artifact — it's a zip containing
`app-release.apk`. Transfer it to an Android phone and install it
(you'll need to allow "install from unknown sources" once, since this
isn't distributed via the Play Store).
