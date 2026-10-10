#!/usr/bin/env bash
# Generates the platform folders of a spike app with the installed Flutter SDK and applies
# the few changes the map libraries need. Used by .github/workflows/spike.yml; it also works
# locally once Flutter is installed:   bash spike/tool/prepare.sh spike/app_maplibre_gl
set -euo pipefail

app_dir="${1:?usage: prepare.sh <spike app directory>}"
cd "$app_dir"
name="$(sed -n 's/^name: *//p' pubspec.yaml)"

# `flutter create` only adds missing files: lib/, test/ and pubspec.yaml are kept.
flutter create --platforms=android,web --org dev.mts.spike --project-name "$name" . >/dev/null

# Release builds need network access for the base map tiles.
manifest=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.INTERNET' "$manifest"; then
  sed -i 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#&\n    <uses-permission android:name="android.permission.INTERNET"/>#' "$manifest"
fi
grep -q 'android.permission.INTERNET' "$manifest"

# The `maplibre` package needs maplibre-gl-js on the page (maplibre_gl injects its own).
if grep -q '^  maplibre:' pubspec.yaml; then
  tags='  <script src="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.js" integrity="sha384-5+cfbwT0iiub6VsQAdn6yz16nr6sDiQoHx6tm4O8OVYXHYOxcffFmCJBL0dgdvGp" crossorigin="anonymous"></script>\n  <link rel="stylesheet" href="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.css" integrity="sha384-uTttxo/aOKbdE5RlD/SPzSDoDmNvGlUYPjONi2MN/b7c9HPSvW07OIuyP7uL6jxK" crossorigin="anonymous">'
  if ! grep -q 'maplibre-gl.js' web/index.html; then
    sed -i "s#</head>#${tags}\n</head>#" web/index.html
  fi
  grep -q 'maplibre-gl.js' web/index.html
fi

# Workaround for maplibre_android 0.3.6: its published build.gradle.kts applies the ktlint
# Gradle plugin without a version, so the app must declare it (as the package's own example
# app does in android/settings.gradle.kts).
if grep -q '^  maplibre:' pubspec.yaml; then
  settings=android/settings.gradle.kts
  [ -f "$settings" ] || { echo "expected $settings (Kotlin DSL) from flutter create" >&2; exit 1; }
  if ! grep -q 'org.jlleitschuh.gradle.ktlint' "$settings"; then
    sed -i 's#^\([[:space:]]*\)id("dev.flutter.flutter-plugin-loader").*#&\n\1id("org.jlleitschuh.gradle.ktlint") version "14.0.+" apply false#' "$settings"
  fi
  grep -q 'org.jlleitschuh.gradle.ktlint' "$settings"
fi

flutter pub get >/dev/null
echo "prepared $name in $app_dir"
