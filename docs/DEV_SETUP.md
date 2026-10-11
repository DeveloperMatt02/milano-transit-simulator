# Development setup

What you need on your machine, phase by phase. The author's machine runs **Fedora Linux**; commands use `dnf`. There is no macOS requirement (iOS is built in CI).

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

## F3 · Dart core (no local toolchain needed)

`packages/transit_core` is pure Dart. GitHub Actions (*Dart core* workflow) analyzes it, runs the tests and the benchmark, and runs a smoke test on the real GTFS feed. Locally, once Flutter is installed (next section), from `packages/transit_core`:

```bash
dart pub get
dart test                                            # unit, parity and GTFS fixture tests
dart run benchmark/engine_benchmark.dart             # timings; --check enforces the budgets
GTFS_DIR=../../data/gtfs dart test test/real_gtfs_test.dart   # after scripts/build_gtfs.py
```

Golden data and fixtures are regenerated from the repository root with `node packages/transit_core/tool/make_golden.js` and `python3 packages/transit_core/tool/make_fixtures.py`.

The F2 map spike (APKs built by CI and installed on the phone) is archived in [docs/benchmarks/f2-map-spike](benchmarks/f2-map-spike/README.md).

## F4 onwards · Flutter on Fedora


The official guide targets [Linux → Android](https://docs.flutter.dev/get-started/install/linux/android); on Fedora the steps are the same with `dnf` instead of `apt`:

1. **System packages**
   ```bash
   sudo dnf install -y curl git unzip xz zip which mesa-libGLU android-tools chromium
   ```
   `android-tools` provides `adb` for the phone; `chromium` is the browser Flutter uses for the web target:
   ```bash
   echo 'export CHROME_EXECUTABLE=/usr/bin/chromium-browser' >> ~/.bashrc
   ```
2. **Flutter SDK** — either let VS Code install it (Flutter extension → *Flutter: New Project* → *Download SDK*) or download the stable bundle from the Flutter site and extract it to `~/development/flutter`, then add it to the `PATH`:
   ```bash
   echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
   ```
   Use **Flutter 3.47.7**, the version pinned in CI ([ADR 0005](adr/0005-map-library-maplibre-gl.md)): from a git checkout of the SDK, `git checkout 3.47.7`; with the downloadable bundle, pick 3.47.7 from the SDK archive.
3. **Android Studio** — download the Linux `.tar.gz` from developer.android.com, extract it (e.g. to `~/development/android-studio`) and run `bin/studio.sh`. Prefer the tarball over the Flatpak: the Flatpak sandbox hides the Flutter SDK and `adb` from the IDE. From *SDK Manager* install: SDK Platform, Command-line Tools, Build-Tools, Platform-Tools. The bundled JDK (21) is the one the map library needs.
4. **Phone instead of emulator** — on the OnePlus enable *Developer options* (tap *Build number* seven times) and *USB debugging*, connect it and accept the prompt; `adb devices` must list it. If it shows `no permissions`, unplug/replug after installing `android-tools` (it ships the udev rules) or reboot.
5. **Emulator (optional)** — needs hardware virtualisation: `grep -cE '(vmx|svm)' /proc/cpuinfo` must print 1 or more, and your user must be able to open `/dev/kvm` (`sudo usermod -aG kvm $USER`, then log out and in). In *Device Manager* create a device with an x86_64 image.
6. **Licenses and check**
   ```bash
   flutter doctor --android-licenses
   flutter doctor -v
   ```
   For this project *Flutter*, *Android toolchain* and *Chrome* must be green; *Linux toolchain* and *Xcode* can be ignored.

Hardware: the Flutter docs list 8 GB of RAM as the minimum (16 GB recommended) and ~11 GB of disk.

## iOS without a Mac

- CI builds the iOS app on a GitHub-hosted macOS runner (unsigned `.app`/`.ipa` as an artifact) to keep the code compiling for iOS.
- Running it on an iPhone or publishing to TestFlight/App Store requires an Apple Developer account and signing certificates stored as CI secrets — planned only when needed.
