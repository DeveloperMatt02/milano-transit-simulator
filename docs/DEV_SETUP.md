# Development setup

What you need on your machine, phase by phase. Everything below targets **Ubuntu 20.04 LTS or later**; there is no macOS requirement (iOS is built in CI).

## Today (JS Lite + data pipeline)

```bash
node --version      # >= 20
python3 --version   # >= 3.10
npm test && npm run test:py
npm run bench       # engine micro-benchmark (informational)
```

## F1 · Real GTFS feed

The pipeline reads the feed from `data/raw/gtfs.zip` (git-ignored):

```bash
python3 scripts/download_open_data.py --gtfs          # feed (~35-60 MB, validated) + tpl_fermate/tpl_orari CSVs
python3 scripts/build_gtfs.py                         # -> data/gtfs/ (≈15-30 s, up to ≈1 GB RAM for a full-network window)
GTFS_REAL=1 python3 -m unittest tests.python.test_gtfs.RealFeed   # optional smoke test on the real feed
```

In CI the deploy workflow downloads and builds it by itself (Monday and Thursday, plus every push to `main`).

## F2 onwards · Flutter

Follow the official guide for [Linux → Android](https://docs.flutter.dev/get-started/install/linux/android) (and add Chrome for the web target). In short:

1. **System packages**
   ```bash
   sudo apt-get update -y && sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa
   sudo apt-get install -y libc6:amd64 libstdc++6:amd64 lib32z1 libbz2-1.0:amd64   # Android Studio
   ```
2. **Flutter SDK** — either let VS Code install it (Flutter extension → *Flutter: New Project* → *Download SDK*) or download the stable bundle from the Flutter site and extract it to `~/development/flutter`, then add it to the `PATH`:
   ```bash
   echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
   ```
   The exact Flutter version is pinned by the project in F2 (CI and local must match).
3. **Android Studio** (Koala 2024.1.1 or later) with, from *SDK Manager*: SDK Platform, Command-line Tools, Build-Tools, Platform-Tools, Emulator. Create an emulator with an x86_64 image and *Hardware – GLES 2.0* graphics.
4. **Licenses and check**
   ```bash
   flutter doctor --android-licenses
   flutter doctor -v
   ```
   For this project, `flutter doctor` must be green for *Flutter*, *Android toolchain* and *Chrome*. The *Linux toolchain* and *Xcode* lines can be ignored.
5. **Web** — Google Chrome, or Chromium with `export CHROME_EXECUTABLE=$(which chromium)`.

Hardware: 8 GB RAM is the minimum the Flutter docs list (16 GB recommended) and the Android emulator needs hardware virtualisation (KVM) enabled in the BIOS.

## iOS without a Mac

- CI builds the iOS app on a GitHub-hosted macOS runner (unsigned `.app`/`.ipa` as an artifact) to keep the code compiling for iOS.
- Running it on an iPhone or publishing to TestFlight/App Store requires an Apple Developer account and signing certificates stored as CI secrets — planned only when needed.
