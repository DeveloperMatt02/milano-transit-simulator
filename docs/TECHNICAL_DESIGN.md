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

* Use the city's GTFS feed (if/when available) for real stop-by-stop times instead of synthesised ones.
* Snap surface routes to the street network (e.g. OSRM or OSM route relations).
* Add the suburban railway (Passante / S lines) and the M4/M5 extensions as they open.
* Heat-map mode showing frequency per segment and time of day.
* Journey planner between two stations using the synthetic timetable.
