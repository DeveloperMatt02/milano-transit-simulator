# F2 · Map library spike

Throw-away code that decides which Flutter map library the app will use ([ADR 0001](../docs/adr/0001-flutter-multiplatform-app.md)). It is removed after F3.

**Outcome (2026-10-11):** `maplibre_gl` — see [ADR 0005](../docs/adr/0005-map-library-maplibre-gl.md) and the raw numbers in [results/](results/).

```text
spike/
├── map_spike_common/   # shared: metro geometry, simulated vehicles, measurements, benchmark page (+ tests)
├── app_maplibre_gl/    # MapBackend with maplibre_gl (maplibre.org, method channel)
├── app_maplibre/       # MapBackend with maplibre (josxha, FFI/JNI on mobile)
└── tool/
    ├── export_metro.py # assets/metro_lines.json from js/data/metro-network.js
    └── prepare.sh      # flutter create (android, web) + INTERNET permission + maplibre-gl-js for `maplibre` on the web
```

The two apps differ only in their `MapBackend` (about 60 lines each), so the comparison measures the libraries and nothing else. Platform folders are not committed: CI generates them with the same Flutter version that builds the apps.

## What the benchmark measures

N vehicles (150, 300, 1,000, 3,000) move along the metro lines; their positions are pushed to a GeoJSON source **every frame** or **10 times per second**. For each combination (3 s warm-up, 15 s measurement):

| Column | Meaning |
| --- | --- |
| tick p50 / p95 | interval between animation frames; 16.7 ms = 60 fps, 8.3 ms = 120 fps |
| ticks > 16.7 ms | share of frames slower than 60 fps — the ADR 0001 criterion is p95 ≤ 16.7 ms at 300 vehicles |
| update p50 / p95 | time for the library to accept a new vehicles GeoJSON (serialisation + platform channel) |
| build / raster p95 | Flutter's own frame phases; the native map view may render outside them |
| sent / skipped | updates sent, and updates skipped because the previous one was still in progress |
| RSS | memory of the app process (not available on the web) |

Not measured automatically: whether the map itself looks smooth (native rendering happens outside Flutter's frame timing). Report it by eye with the numbers.

## How to run it

CI (`.github/workflows/spike.yml`) builds both apps on every push to `f2-map-spike`. From the workflow run:

- **Android:** download `apk-app_maplibre_gl` / `apk-app_maplibre`, install them on the phone (they can coexist), open, press **Run benchmark** (~2.5 min, keep the screen on), then **Copy results**.
- **Web:** download `web-…`, unzip, `python3 -m http.server 8000 -d <folder>`, open <http://localhost:8000> in Chrome, same buttons.

Locally (after installing Flutter, see [DEV_SETUP](../docs/DEV_SETUP.md)): `bash spike/tool/prepare.sh spike/app_maplibre_gl && cd spike/app_maplibre_gl && flutter run --release`.
