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

## F2 · Map spike (no local toolchain)

The spike apps are compiled by GitHub Actions (`.github/workflows/spike.yml`): every push to the `f2-map-spike` branch produces a web build and an Android APK as downloadable artifacts. To test on an Android phone:

1. GitHub → *Actions* → latest *Map spike* run → *Artifacts* → download `apk-…` and unzip it.
2. Copy the `.apk` to the phone (USB, cloud drive or e-mail) and open it; Android asks to allow installs from that source once.
3. In the app press **Run benchmark**, wait for the end, press **Copy results** and paste them in the chat.

The web build is tested by unzipping the `web-…` artifact and serving the folder, e.g. `python3 -m http.server 8000 -d web` and opening <http://localhost:8000>.

## F3 onwards · Flutter on Fedora

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
