# ADR 0001 · Flutter for the multiplatform app

**Status:** Accepted (2026-10-10). Spike passed and map library chosen on 2026-10-11: [ADR 0005](0005-map-library-maplibre-gl.md) (`maplibre_gl`).

## Context

The simulator is a static vanilla-JS web app. The goal is one product available on the **web** (GitHub Pages), **Android** and **iOS**, with native-quality gestures, bottom sheets and map performance on phones.

Constraints:
- the author develops on **Fedora Linux, without a Mac**: iOS can be built only on macOS CI runners, and cannot be run locally;
- no backend, no API keys, no paid services (OpenFreeMap base map, open data);
- the app animates 150–300 vehicles today and potentially a few thousand with GTFS (see the [baseline review](../reviews/F0-baseline-review.md#h1--engine-hot-paths-scale-linearly-with-the-number-of-trips-of-the-day)).

## Options

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Flutter** (Dart) | One typed codebase for web, Android, iOS; native MapLibre on mobile; native sheets/gestures; strong testing (unit, widget, golden) | Full rewrite of the UI; heavier first load on the web (engine + CanvasKit/Skwasm); needs a build step |
| B. Capacitor around the current web app | Days instead of weeks; reuses all code | WebView map on phones; app feels like a website; two-speed DOM loop on low-end devices |
| C. React Native / Expo + MapLibre RN | Native maps; JS/TS skills reuse | Web support through react-native-web is weaker for maps; second rewrite path for web |
| D. PWA only | Zero new stack | No store presence; limited iOS install experience |

## Decision

**Option A — Flutter**, gated by a spike (F2) with explicit criteria:

- **must pass:** 300 animated vehicles (today's metro peak is ~150) with p95 frame time ≤ 16.7 ms on the web (Chrome, desktop) and on Android — on a mid-range device if available, otherwise on the emulator, whose results are recorded as indicative;
- **measured, not gating:** 3,000 vehicles (whole network with GTFS), memory use and web bundle size; these decide whether the "all vehicles" view needs viewport culling or aggregation at low zoom.

If the must-pass criteria fail, fall back to **option B** for the mobile apps and keep the JS app as the web version.

Map library candidates, both MapLibre-based and both covering Android, iOS and web:
- [`maplibre_gl`](https://pub.dev/packages/maplibre_gl) — mature, published by maplibre.org (0.26.x);
- [`maplibre`](https://pub.dev/packages/maplibre) — modern rewrite, native bindings through FFI/JNI on mobile, maplibre-gl-js on the web (0.3.x, pre-1.0).

The spike measures frame time when updating a GeoJSON source of N moving points at 60 Hz and at 10 Hz with client-side interpolation, plus memory and web bundle size, and picks the library on these numbers.

Initial technical choices (revisited only with a reason):
- pure-Dart core package (`packages/transit_core`): time model, calendar, scheduler, GTFS model, simulation — no Flutter imports, tested with `dart test`;
- state: Riverpod; routing: go_router (query parameters `?simulation`, `?lang` preserved on the web);
- localisation: `gen-l10n` with ARB files ported from `js/i18n.js`;
- themes: `ThemeData` + `ThemeExtension` for Noorda light/dark and Fiord, same OpenFreeMap styles;
- fonts bundled as assets (Archivo, IBM Plex Sans/Mono — SIL OFL) so the app works offline after install.

## Consequences

- The web app needs a build (`flutter build web --base-href /milano-transit-simulator/`); opening `index.html` from disk no longer works for the Flutter version.
- The JS app remains as the "lite" version during and after the migration ([ADR 0003](0003-js-lite-deprecation.md)).
- Development of Dart code cannot be compiled or tested inside the Claude workspace (pub.dev and the Flutter SDK storage are not reachable from it): tests run on the author's machine and in GitHub Actions.
- iOS: CI produces an unsigned build on a macOS runner; distribution (TestFlight/App Store) requires an Apple Developer account and is out of scope until then.
