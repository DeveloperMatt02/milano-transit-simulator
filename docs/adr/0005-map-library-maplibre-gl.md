# ADR 0005 · Map library: maplibre_gl

**Status:** Accepted (2026-10-11). Closes the open point of [ADR 0001](0001-flutter-multiplatform-app.md); Flutter is confirmed as the stack (the go/no-go criteria are met).

## Context

The F2 spike (archived: [docs/benchmarks/f2-map-spike](../benchmarks/f2-map-spike/README.md)) rendered the metro network with 150–3,000 moving vehicles, pushed to a GeoJSON source every frame or at 10 Hz, with two candidate libraries behind the same `MapBackend` interface. Builds: Flutter 3.47.7, arm64 release APKs from GitHub Actions. Device: the author's OnePlus Nord 4 (display at 90 Hz during the runs). Raw results: [maplibre_gl](../benchmarks/f2-map-spike/2026-10-10-oneplus-nord4-maplibre_gl.md), [maplibre](../benchmarks/f2-map-spike/2026-10-10-oneplus-nord4-maplibre.md).

| | `maplibre_gl` 0.27.1 (maplibre.org) | `maplibre` 0.3.6 (josxha) |
| --- | --- | --- |
| Builds for Android and web | as is | needs the ktlint Gradle plugin declared by the app |
| Release APK (R8 on) | works | **map never starts**: `NullPointerException` while creating the platform view; works only with R8 disabled |
| 300 vehicles, every frame — tick p95 / ticks > 16.7 ms | 11.1 ms / 0.7 % ✅ | 11.1 ms / 0.6 % ✅ (no R8) |
| GeoJSON update p50 at 300 / 3,000 vehicles | 11.5 / 57.8 ms (async, method channel) | 2.0 / 14.1 ms (sync, FFI/JNI) |
| 1,000 vehicles, every frame — ticks > 16.7 ms | 37 % | 27 % |
| 3,000 vehicles, every frame — ticks > 16.7 ms (p95) | 51 % (55 ms) | 100 % (33 ms) |
| Smoothness by eye | smooth at 300, fairly smooth at 3,000, panning responsive | same |
| RSS at 300 vehicles | ~360 MB | ~330 MB |

Observations:
- Both pass the must-pass criterion of ADR 0001 (300 vehicles, p95 ≤ 16.7 ms on Android).
- `maplibre` accepts updates 4–6× faster, but the work runs synchronously inside the frame; `maplibre_gl` is slower per update but asynchronous, so it blocks the UI less at high counts.
- At 3,000 vehicles neither library keeps 60 fps with full-network updates every frame: the cost is in serialising and transferring all positions, not in drawing.
- Single-update latency is higher at 10 Hz than every frame on both libraries, most likely CPU frequency scaling at low load; it does not change the conclusion.
- The web build was compiled for both libraries but not benchmarked: both use maplibre-gl-js on the web.

## Decision

Use **`maplibre_gl`** (0.27.x) for the Flutter app.

- It meets the criterion, works in optimised release builds without changes, and is maintained by the MapLibre organisation.
- `maplibre` is faster at pushing data but, at 0.3.6, cannot ship an R8-optimised Android build in our setup and has a history of release-build issues (see its changelog). Shipping without R8 (larger, non-obfuscated APK) or reverse-engineering the missing keep rule is not worth it while `maplibre_gl` is adequate.
- The app keeps the map behind an interface like the spike's `MapBackend`, so a later switch costs one adapter.

Design consequences for F4 (from the measurements):
- **Viewport culling**: push only vehicles inside the visible area (plus a margin); at low zoom, aggregate or thin out vehicles. Target: ≤ ~500 points per update.
- **Update cadence**: positions every frame when few vehicles are visible; fall back to a lower rate when the update time exceeds the frame budget (adaptive, measured at runtime as in the spike).
- **One update in flight** at a time (as in the spike): if the previous update has not completed, skip rather than queue.

## Revisit when

- `maplibre` reaches 1.0, or its release builds work with R8, **and** update cost becomes the bottleneck of the app; or
- `maplibre_gl` stops being maintained or lags behind MapLibre Native/GL JS.

## Consequences

- Flutter is pinned to **3.47.7** in CI (the version used for the measurements) and on the author's PC.
- The `spike/` folder stayed until the end of F3 as a reference and was then removed; results and lessons are in [docs/benchmarks/f2-map-spike](../benchmarks/f2-map-spike/README.md), the code in git history (commit `fae2cc7`).
