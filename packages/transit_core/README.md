# transit_core

The timetable and simulation engine of Milano Transit Simulator, in pure Dart (no Flutter). The Flutter app (roadmap F4) builds on it; the tests run it against the JavaScript engine of the Lite app.

| Module | What it does | JS counterpart |
| --- | --- | --- |
| `time.dart` | Service-day timeline (03:00 → 27:00), `parseHHMM`, `formatClock`, `isActiveAt` | `js/utils.js` |
| `calendar.dart` | `CivilDate`, Easter and Milan holidays, day types, **Milan wall clock (CET/CEST) without a time-zone database** | `js/utils.js` |
| `geo.dart` | Haversine distance, bearing, `jsRound`, `Place` and `PlaceRegistry` | `js/utils.js` |
| `synthetic.dart` | Readers of `js/data/*.js` and the synthetic scheduler (service levels → trips) | `js/scheduler.js` |
| `gtfs.dart` | Reader of the GTFS datasets (format v1, built by `scripts/build_gtfs.py`), coverage rule, trips of a service day, polylines | — |
| `schedule.dart` | `ScheduleComposer`: for each line and day, GTFS when it covers the date, otherwise synthetic (ADR 0004) | — |
| `engine.dart` | `TransitEngine`: vehicle positions and departure boards, with time-bucket and per-place indexes | `js/simulation-engine.js` |
| `clock.dart` | `SimulationClock`: real-time or manual, speed, pause, wrap at 27:00 | `js/simulation-engine.js` |

```dart
final composer = ScheduleComposer(synthetic: scheduler, gtfs: dataset); // dataset optional
final day = composer.compose(milanTime(DateTime.now()).serviceDate);
final engine = TransitEngine(day.trips, composer.places());
final vehicles = engine.activeVehicles(clock.simTime);
final board = engine.departures('duomo', clock.simTime);
// day.estimatedLines -> lines shown with estimated times (notice in the UI)
```

## Parity with the JavaScript engine

`tool/make_golden.js` runs the JS engine on fixed scenarios and writes `test/golden/js_engine.json`: every metro trip of the three day types and a few surface lines (FNV-1a hash over every stop time), vehicle positions at five moments, departure boards, Easter dates, the day type of every day of 2026, Milan wall-clock conversions around the DST changes. `test/parity_test.dart` and `test/time_calendar_test.dart` require the Dart engine to give the same results. Points that matter for identical results:

- JavaScript iterates integer-like object keys (`"9901"`) first, in ascending order: `jsKeyOrder`;
- `Array.prototype.sort` is stable, Dart's `List.sort` is not: `sortTripsByStart` and the board sort break ties by input order;
- `Math.round` rounds halves towards +∞: `jsRound`;
- floating-point expressions keep the JS grouping (haversine).

## Performance

The JS engine scans every trip of the day on each frame (F0 review, finding H1). Here a frame only visits the trips of one time bucket, a departure board only the trips that serve the place, and the position inside a trip is a binary search. `benchmark/engine_benchmark.dart` measures it; with `--check` (CI) it fails above the budgets for ≈59,000 trips.

## Commands

From this folder (Flutter 3.47.7 / Dart 3.13, see `docs/DEV_SETUP.md`):

```bash
dart pub get
dart analyze
dart test
dart run benchmark/engine_benchmark.dart [--check] [--gtfs ../../data/gtfs]
GTFS_DIR=../../data/gtfs dart test test/real_gtfs_test.dart
```

From the repository root, after changing `js/` or the GTFS pipeline:

```bash
node packages/transit_core/tool/make_golden.js        # --check in CI
python3 packages/transit_core/tool/make_fixtures.py   # --check in CI
```

## Known limitations

- On the two daylight-saving nights the hour between 02:00 and 03:00 is approximated (as in the JS app); GTFS times are taken as wall-clock times of their date.
- After the last day of the GTFS window, night trips that the feed dates to the next day are missing between 00:00 and 03:00 (roadmap open point on the fallback rule).
