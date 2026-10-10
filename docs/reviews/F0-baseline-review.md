# F0 · Baseline review

**Scope:** the whole repository at commit `ab28ce0` (v2), before any roadmap work.
**Date:** 2026-10-10
**Method:** full read of the runtime modules, data pipeline, tests and workflows; test suites run; engine hot paths benchmarked (`npm run bench`).

---

## 1. Health check

| Check | Result |
| --- | --- |
| `npm test` (node:test) | 44 / 44 pass |
| `python -m unittest discover -s tests/python` | 12 / 12 pass |
| Dependencies | Leaflet 1.9.4 JS and CSS (SRI pinned); MapLibre GL 5.24.0 JS and CSS and maplibre-gl-leaflet 0.1.4 (version pinned, **no SRI**) |
| Data vintage | Open data timetable *INV2024-2025* (winter 2024–25) |

The codebase is in good shape: modules are small and single-purpose, the engine is a pure function of `(trip, time)`, rendering is split between per-frame map work and throttled DOM work, and the docs match the code. The findings below are about **what changes when the project moves to real GTFS timetables and to Flutter**, plus a few hygiene items.

## 2. Findings

Severity: **High** blocks a roadmap phase · **Medium** should be fixed in the phase that touches the code · **Low** hygiene.

### H1 · Engine hot paths scale linearly with the number of trips in the simulation

`TransitSimulation.getActiveVehicles()` walks the whole sorted timetable on every animation frame: its early `break` (`startTime > t + 24 h`) never fires in practice, because every trip starts before 27:00 and `t + 24 h` is at least 27:00. `getStationDepartures()` calls `trip.stationIds.indexOf(stationId)` on every trip it receives, four times per second while a board is open, and `getVehicleState()` scans the stop list of each running trip linearly.

**Today this is fine**, because `app.js` bounds the work: the simulation holds either the metro timetable (~3,000 trips) or the timetable of the one selected surface line, and a surface board only scans the lines serving that stop. The cost becomes a problem as soon as one simulation holds the whole network — the natural design with GTFS (all vehicles on the map, metro and surface boards from one timetable).

Measured with `npm run bench` (Node 22, desktop-class VM, 08:15 weekday, warm JIT, 60 runs per cell, two runs agree within ~10 %). The scaled rows are illustrative volumes (the metro timetable copied 5× and 20×), not a model of the feed; map rendering is not included:

| Trips in simulation | Running vehicles | `getActiveVehicles` per frame (median) | Share of a 60 fps frame | `getStationDepartures` (median) |
| ---: | ---: | ---: | ---: | ---: |
| 2,958 (today, metro) | 148 | 0.3 ms | 2 % | 0.3 ms |
| 14,790 | 740 | 1.6 ms | 9–10 % | 1.9 ms |
| 59,160 | 2,940 | 6.6–7.0 ms | 40–42 % | 13–14 ms |

The board figures of the scaled rows are inflated (every copy serves Duomo), but the per-frame cost is not: it is linear in the trips held. Phones are slower than this machine (estimate: several times for a mid-range device), and the GeoJSON/marker update for thousands of points comes on top — measured in the F2 spike.

**Recommendation (F3 in the Dart core, F4 design; optionally back-ported to the JS lite):**
- time-bucket index (e.g. 5-minute buckets → trips active in the bucket) so each frame only visits candidate trips;
- `stopId → [(tripIndex, stopIndex)]` index sorted by departure time, with binary search for the board horizon;
- binary search on `stopTimes` inside `getVehicleState()` (surface trips have 30–60 stops);
- viewport culling and, at low zoom, aggregation of vehicles in the map layer (F4);
- keep the bench as a regression guard, with a time budget asserted in CI on a reduced dataset (F3).

### H2 · Static committed data cannot carry a GTFS feed that expires every few weeks

Each GTFS release covers only ~4–5 weeks (e.g. 14 Sep – 19 Oct 2026). Committed data would make the app silently show *no service* after expiry.

**Recommendation (F1):** scheduled GitHub Actions workflow that downloads the feed, rebuilds the datasets and redeploys; the app checks the feed's validity window at start-up and falls back to the synthetic scheduler (today's engine) outside it, with a visible notice.

### H3 · Feed size requires a compact runtime format

The current release is ~60 MB zipped (Comune di Milano portal); past releases weighed ~260–770 MB unzipped (Mobility Database history). `stop_times.txt` cannot be shipped as is.

**Recommendation (F1):** pre-compute *patterns* (unique stop sequences) and *time profiles* (relative arrival/departure offsets shared by many trips); store each trip as `(pattern, profile, start time, service id)`. Export only the service days inside a rolling window, and set an explicit size budget for the web build (target: ≤ 5 MB compressed for the whole dataset), enforced by a pipeline test.

### M1 · GitHub Pages deploys even when tests fail

`pages.yml` and `ci.yml` are independent workflows triggered by the same push; a red test run still publishes the site.

**Recommendation (F1, when the workflows are touched):** a single workflow with `deploy` → `needs: [javascript, python]`, or `workflow_run` on CI success.

### M2 · Missing Subresource Integrity on three CDN resources

`maplibre-gl@5.24.0` (script and stylesheet) and `@maplibre/maplibre-gl-leaflet@0.1.4` are loaded from unpkg without `integrity`, unlike Leaflet. A compromised or altered package would run with full page privileges.

**Recommendation (F1):** add `integrity` + `crossorigin` to all three, or vendor them.

### M3 · One timetable all year

The synthetic scheduler applies the winter 2024–25 service levels on every date, so summer timetables (reduced August service), strikes and temporary diversions are not represented. GTFS removes most of this; the synthetic fallback should state the vintage it uses.

**Recommendation:** documented in ADR 0002; the fallback notice shows the data vintage.

### M4 · Hand-maintained metro topology

The metro topology (branches, station order) is hand-written in `build_metro_network.py`. With GTFS, the topology can be derived from `trips` + `stop_times` + `shapes`, and the hand-written version becomes a cross-check.

**Recommendation (F1):** derive from GTFS, keep the current builder as a validation test (same stations, same branch junctions).

### L1 · `app.js` is a 39 KB controller

State, rendering, panels, search, sheets and settings live in one closure. It works and is well organised internally, but it is the module that does not port to Flutter one-to-one.

**Recommendation (F4):** in Flutter split by feature (`lines/`, `stations/`, `vehicles/`, `settings/`, `timeline/`) with state in providers; no change in the lite version.

### L2 · Minor inconsistencies

- `themes.js` reads/writes `localStorage` directly instead of `TransitUtils.storage` (same behaviour, two code paths).
- The real-time loop calls `Intl.DateTimeFormat.formatToParts` twice per frame (`sim.tick()` and `dayTypeFor(milanClock())`); computing the day type once per UI refresh is enough.

Both are cosmetic; fix only if the files are touched.

## 3. What to keep in the Flutter port

- The **service-day time model** (03:00 → 27:00) — GTFS uses the same convention (times past 24:00).
- **Stateless vehicle positions** — essential for timeline scrubbing and 60× playback.
- The **two-speed loop** (map every frame, panels ≤ 4×/s).
- The **WCAG contrast test** for line badges and the **i18n parity test**.
- The existing JS test-suites as the **reference behaviour**: F3 adds parity tests that run the same fixtures through JS and Dart.
