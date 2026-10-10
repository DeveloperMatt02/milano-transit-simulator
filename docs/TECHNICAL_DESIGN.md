# Technical Design

**Project:** Milano Transit Simulator

---

## Table of contents

1. [Goal](#1-goal)
2. [Datasets](#2-datasets)
3. [Service-day time model](#3-service-day-time-model)
4. [Timetable synthesis](#4-timetable-synthesis)
5. [Vehicle state](#5-vehicle-state)
6. [Departure boards and statistics](#6-departure-boards-and-statistics)
7. [Assumptions and limitations](#7-assumptions-and-limitations)
8. [Possible extensions](#8-possible-extensions)
9. [GTFS datasets (format v1)](#9-gtfs-datasets-format-v1)

---

## 1. Goal

Show, on a map, a plausible picture of where Milan's metro trains and surface vehicles are at any moment of any day, using only open data. The result must be:

* **credible** – frequencies, first and last runs, branch patterns and day types follow the published service levels;
* **honest** – the UI states clearly that positions are simulated;
* **deterministic and testable** – the same inputs always produce the same timetable;
* **light** – no backend, runs smoothly on a phone.

## 2. Datasets

### 2.1 Sources

| File | Publisher | License | Content |
| --- | --- | --- | --- |
| `tpl_metroorari.csv` | Comune di Milano | CC BY 4.0 | One row per metro route variant (branch × direction) and day type: trips per day and per time band, first/last run |
| `tpl_orari.csv` | Comune di Milano | CC BY 4.0 | Same structure for surface route variants |
| `tpl_sequenza.csv` | Comune di Milano | CC BY 4.0 | Ordered stop list of every surface route variant |
| `tpl_fermate.csv` | Comune di Milano | CC BY 4.0 | Surface stops with description and WGS84 coordinates |
| Overpass export | OpenStreetMap | ODbL | Coordinates of metro station nodes |

The committed data comes from the *INV2024-2025* (winter 2024–25) timetable.

### 2.2 Generated files

**`metro-network.js`** – 125 stations, 5 lines. The topology is hand-written in `build_metro_network.py` because OSM route relations are split per direction and branch; coordinates come from OSM (exact name match first, then a manual table, then a logged substring match; the build fails if a station cannot be located).

```jsonc
{
  "stations": { "loreto": { "id": "loreto", "name": "Loreto", "lat": 45.48, "lon": 9.21,
                            "lines": ["M1", "M2"], "interchanges": ["M2"] } },
  "lines": { "M1": { "id": "M1", "name": "Linea M1 (Rossa)", "color": "#F12D2D",
                     "paths": { "trunk": [...], "branch_rho": [...], "branch_bisceglie": [...] } } }
}
```

Branches share their junction station with the trunk (e.g. every M1 path touches `pagano`), which lets the scheduler join paths without duplicating stations.

**`metro-frequencies.js`** – per line and day type (`L` weekday, `S` Saturday, `F` Sunday/holiday):

```jsonc
{ "daily_trips": 236, "peak_headway": 203, "mid_headway": 300, "evening_headway": 554,
  "first_departure": "05:40", "last_arrival": "24:53" }
```

All route variants of a line are summed and divided by two (two directions) to obtain the frequency on the trunk. The dataset gives trips per time band but not the band length; two hours reproduces ATM's published headways (e.g. M3 peak ≈ 3½ min), so `headway = 7200 s / trips_per_direction`, clamped to a realistic range.

**`surface-network.js`** – 142 lines, 423 route variants, 4,690 stops. For each route variant and day type it stores the three headways and a service window (`service_start`, `service_end`) in service-day time. A day type is **absent** when the route does not run that day – the simulator does not fall back to the weekday timetable.

### 2.3 Data fixes compared with the first prototype

| Problem | Fix |
| --- | --- |
| Lambrate FS missing from M2 | Added between Udine and Piola |
| Portello listed on the M1 Rho branch in the build script | Removed (Portello is M5 only) |
| First/last run compared as strings, so `00:13` counted as the *first* run of M1 | Times before 03:00 are mapped after 24:00 before taking min/max |
| Surface routes without Sunday service fell back to the weekday timetable | Missing day type = no service |
| 24-hour lines (90/91) needed a runtime heuristic | Detected at build time and stored as a 03:00–27:00 window |

## 3. Service-day time model

Transit timetables do not end at midnight: the last metro trains of Friday evening arrive around 01:00 on Saturday. The simulator therefore uses a **service day** from 03:00 to 03:00, with times expressed in seconds from the midnight that opens it:

| Wall clock | Service time |
| --- | --- |
| 05:40 | 05:40 (20,400 s) |
| 23:30 | 23:30 (84,600 s) |
| 00:30 (next calendar day) | **24:30** (88,200 s) |
| 02:59 (next calendar day) | **26:59** |

* In real-time mode the clock is Milan's wall-clock time (`Europe/Rome`, via `Intl.DateTimeFormat`), so visitors in other time zones see the city as it is now.
* `toServiceTime()` converts the wall clock; `formatClock()` converts back for display.
* The day type is taken from the calendar day of the *service* day, so at 00:30 on Sunday the Saturday timetable is still in use.
* In manual mode the clock wraps from 27:00 back to 03:00; the timeline covers the full 24 hours.
* A trip is active at `t` if `start ≤ t ≤ end` **or** `start ≤ t + 24 h ≤ end`, which covers the few night trips that run past 27:00.

Holidays follow the Italian calendar (New Year, Epiphany, Easter Monday, 25 April, 1 May, 2 June, 15 August, 1 November, 8/25/26 December) plus Sant'Ambrogio (7 December), Milan's patron saint; Easter is computed with the anonymous Gregorian algorithm.

## 4. Timetable synthesis

### 4.1 Headway by time band

| Band | Service time | Headway |
| --- | --- | --- |
| Early morning | before 07:00 | off-peak |
| Morning peak | 07:00–09:30 | peak |
| Off-peak | 09:30–16:30 | off-peak |
| Evening rush | 16:30–19:30 | mean of peak and off-peak |
| Evening | after 19:30 | evening |

### 4.2 Metro

For every line, starting at `first_departure`, one train leaves **each** terminus every `headway(t)` seconds. A trip is kept only if it reaches its terminus by `last_arrival`.

* **M1** alternates Sesto 1° Maggio → Bisceglie and Sesto 1° Maggio → Rho Fieramilano (and the reverse), so each branch gets every second train of the trunk.
* **M2** alternates Cologno Nord and Gessate in the north; in the south one train in three serves Assago Milanofiori Forum and the others Abbiategrasso.
* **M3, M4, M5** run end to end.

Stop times:

```
running time(a → b) = clamp(distance(a, b) / 10 m/s, 50 s, 180 s)
dwell(station)      = 45 s at interchanges, 25 s elsewhere
```

### 4.3 Surface

Each route variant dispatches vehicles from its first stop between `service_start` and `service_end` using the same band logic. Running time is `distance / 4.4 m/s` (≈16 km/h commercial speed) clamped to 20–200 s, with a 15 s dwell at every stop.

To show "N vehicles" next to 142 lines every 250 ms without generating 142 full timetables, `countActiveSurfaceVehicles()` only uses the cached departure times and the cached route duration: a departure `d` is on the road at `t` if `d ≤ t ≤ d + duration`. A unit test checks that this matches the count obtained from the full timetable.

## 5. Vehicle state

For a trip and a time `t`, `getVehicleState()` walks the stop times:

* **STOPPED** if `arrival ≤ t ≤ departure` at a stop – position is the stop;
* **MOVING** if `departure(i) < t < arrival(i+1)` – position is the linear interpolation between the two stops with `f = (t − departure(i)) / (arrival(i+1) − departure(i))`.

The state also carries the heading (for the arrow on the marker), the average speed of the segment, the seconds to the next stop, the progress along the segment and the terminus arrival time. Because it is a pure function of `(trip, t)`, time can jump arbitrarily (timeline scrubbing, 60× playback) without any accumulated state.

## 6. Departure boards and statistics

`getStationDepartures(stationId)` scans the relevant trips (the whole metro timetable, or the timetables of every surface line serving the stop), keeps stops whose departure is still to come within the next two hours, **excludes trips that terminate at that station**, sorts by arrival and keeps the first *N* per `(line, destination)`.

The sidebar statistics are computed, not hard-coded: vehicles currently running, trips scheduled for the day, and number of stations/stops. A line shows "In service" only when at least one of its vehicles is running, and the line panel shows the headway of the current time band.

## 7. Assumptions and limitations

* **Not live.** No real-time feed is used. Delays, disruptions, strikes and short-turn trips are not represented.
* **Even spacing.** Within a band, trains are perfectly regular; the real timetable has irregular gaps, especially at the start and end of service.
* **Band boundaries** (07:00, 09:30, 16:30, 19:30) and the 2-hour band length are assumptions – the dataset does not document them.
* **Running times** are derived from straight-line distance and a constant average speed; acceleration, gradients and speed limits are ignored.
* **Surface geometry** is drawn as straight segments between consecutive stops, not along the streets.
* **Branch patterns** (M1 alternation, M2 one-in-three to Assago) approximate ATM's typical service pattern.
* **Data vintage.** The committed data is the winter 2024–25 timetable; rerun the pipeline to refresh it.

## 8. Possible extensions

* Use the city's GTFS feed for real stop-by-stop times instead of synthesised ones — the feed is now published by the Comune di Milano and is planned for roadmap phase F1 ([ADR 0002](adr/0002-gtfs-primary-data-source.md)).
* Snap surface routes to the street network (e.g. OSRM or OSM route relations).
* Add the suburban railway (Passante / S lines) and the M4/M5 extensions as they open.
* Heat-map mode showing frequency per segment and time of day.
* Journey planner between two stations using the synthetic timetable.

## 9. GTFS datasets (format v1)

Built by `scripts/build_gtfs.py` from the Comune di Milano / AMAT GTFS feed ([ADR 0002](adr/0002-gtfs-primary-data-source.md), [ADR 0004](adr/0004-gtfs-dataset-format-and-refresh.md)) into `data/gtfs/`. The files are not committed: the deploy workflow rebuilds them twice a week. They are read by the Dart core from F3; the JS Lite app keeps using `js/data/`.

### 9.1 Pipeline

1. **Calendar** — `calendar.txt` (weekday flags over a date range) and `calendar_dates.txt` (additions/removals) give the dates of every service. The window covers 14 days from the build day (Europe/Rome) **plus the previous service day**, whose trips after midnight are still running in the early hours of the first day: 15 days, `window.start` = build day − 1. Each service becomes a bit mask over the window (bit *i* = day *i*); services with the same mask are stored once.
2. **Trips** — for every route, `coverage_end` is the last date with trips in the *whole* feed. Only trips whose service runs inside the window are kept.
3. **Stop times** — streamed (the file is ~440 MB); rows are collected per window trip because a trip's rows are scattered through the file, then sorted by `stop_sequence`. Stops without times (non-timepoints) are interpolated, repeated `stop_sequence` values are dropped, non-monotonic times are clamped, trips without a time at the first or last stop or with an unknown route are skipped — all counted in the warnings. A full-network window takes ≈ 26 s and ≈ 820 MB of RAM.
4. **Deduplication** — a *pattern* is route + headsign + stop list + shape; a *profile* is a pattern + arrival offsets + dwell times. A trip is `(start, profile, service)`. On the real feed, ~122,000 trips in a full-network window use ~790 patterns and ~8,000 profiles.
5. **Stops and stations** — only stops used by window trips. Metro stops are matched to the stations of `js/data/metro-network.js` (nearest station on the same line within 400 m, so `LORETO M1` and `LORETO M2` become `loreto`); surface stops keep the readable `tpl_fermate.csv` name when the id matches.
6. **Shapes** — Douglas-Peucker with a 5 m tolerance (≈ 6× fewer points), Google encoded polyline with precision 5.
7. **Output** — written to a temporary directory, checked against the 5 MB gzip budget, then copied over the previous output.

### 9.2 Files

All files carry `"version": 1`. Indices are positions in arrays: `stop`/`station` indices in `network.json`; `pattern.route` → `network.routes`; `pattern.shape` → `shapes.shapes`; `profile.pattern` → `network.patterns`; `trips.profile` → `timetable.profiles`; `trips.service` → `timetable.services`.

**`network.json`**

```jsonc
{
  "stops":    [{ "id": "11490", "name": "…", "lat": 45.46, "lon": 9.19, "wheelchair": 0 | 1 | 2, "station": "duomo" | null }],
  "stations": [{ "id": "duomo", "name": "Duomo", "lat": 45.46, "lon": 9.19, "lines": ["M1", "M3"], "stops": [12, 13] }],  // metro only
  "routes":   [{ "id": "M1", "name": "M1", "long_name": "M1 - Linea Rossa", "mode": "METRO" | "TRAM" | "FILOBUS" | "BUS",
                 "color": "#FF0000" | null, "coverage_end": "2026-10-19" }],
  "patterns": [{ "route": 0, "headsign": "Bisceglie", "stops": [12, 40, 41], "shape": 3 | null }]
}
```

**`timetable.json`**

```jsonc
{
  "window":   { "start": "2026-10-09", "days": 15 },   // previous service day + 14 days
  "services": [31, 96],                               // bit masks over the window days
  "profiles": [{ "pattern": 0, "arrivals": [0, 90, 185], "dwells": [0, 20, 0] }],  // seconds; dwells omitted when all 0
  "trips":    { "start": [19800, 20400], "profile": [0, 0], "service": [0, 0] }    // columnar, sorted by start
}
```

**Times are GTFS times**, not the service-day model of §3: seconds after *noon minus 12 h* of the service date (midnight, except on the two daylight-saving days: 01:00 of the same day when clocks go back, e.g. 2026-10-25; 23:00 of the previous day when they go forward in March). For a trip and a stop *i*: arrival = `start + arrivals[i]`, departure = arrival + `dwells[i]`. The feed mixes two conventions for night trips: some start at 24:00 or later on their service date (≈ 4,500 in a full window, e.g. `25:30` for 01:30), others start before 03:00 on the next service date (≈ 760, night lines NM1–NM4, N25, 90…). The engine must convert every trip to wall-clock time (service date + time) before mapping it to the service-day timeline, and must not assume `start ≥ 03:00`.

**`shapes.json`** — `{ "precision": 5, "shapes": ["encoded polyline", …] }`.

**`meta.json`** — feed publisher and version, `start_date`, the per-mode `end_dates` declared by the feed, `last_service_date`, window, build time, counts, warnings and the CC BY attribution to show in the app.

### 9.3 Using the data

A route is served by GTFS on service date *d* when **all** of these hold: the route is in `network.routes`, *d* is inside the window (`window.start ≤ d < window.start + days`) and `d ≤ coverage_end`. Then the GTFS trips are authoritative — no trips that day means no service. In every other case (route missing, date outside the window, date after `coverage_end`, dataset missing) the app falls back to the synthetic timetable for that route and says so. A trip runs on window day *i* when `services[trip.service] >> i & 1`. Coverage is partial between 00:00 and 03:00 after the last window day: night trips that the feed dates to the following day (starting before 03:00) are not in the window, so the engine treats those hours like a date outside the window.
