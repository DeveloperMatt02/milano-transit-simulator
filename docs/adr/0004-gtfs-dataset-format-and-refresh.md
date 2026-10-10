# ADR 0004 · GTFS dataset format, per-route fallback and refresh

**Status:** Accepted (2026-10-10). Refines [ADR 0002](0002-gtfs-primary-data-source.md) with what the real feed (version 423) showed in F1.

## Context

Findings on the feed downloaded on 2026-10-10:

- `stop_times.txt` is 438 MB (4.1 M rows) for 175,790 trips over 14 Sep – 19 Oct 2026; rows of a trip are **not contiguous** in the file.
- No `calendar.txt` rows: services are defined in `calendar_dates.txt` only.
- **Coverage differs by mode and by route.** `feed_info.txt` declares `surface_end_date = 2026-10-02` and `mm_end_date = 2026-10-15`; in practice trams stop on 2 Oct, about half of the bus routes on 3 Oct, while the metro and the other bus routes run until 18–19 Oct. On 2026-10-10 the feed has **no tram trips at all**.
- Metro stop ids are names (`LORETO M1`, `LORETO M2`), there are no parent stations; surface `stop_id`s equal the `id_amat` of `tpl_fermate.csv` (96 %, same coordinates), whose names are readable while the feed's are lower-case.
- Only the five metro routes have a `route_color`; trolleybuses are `route_type = 3` like buses.
- Some names are UTF-8 decoded as Latin-1 upstream (`libertÃ\xa0`).
- Night trips use two conventions: times past 24:00 on the service date, or times before 03:00 on the next service date.

## Decision

1. **Fallback per route and per day** (not per feed). Every route carries `coverage_end`, the last date with trips in the feed. For a date inside the dataset window and ≤ `coverage_end` the GTFS times are authoritative (no trips means no service); otherwise — after `coverage_end`, outside the window, route or dataset missing — the app uses the synthetic scheduler for that route and shows a notice. *Open point: revisit this rule with the author after F3 (e.g. partial-day coverage, notice wording).*
2. **Compact format v1** (documented in [TECHNICAL_DESIGN §9](../TECHNICAL_DESIGN.md#9-gtfs-datasets-format-v1)): patterns, shared time profiles, columnar trips, services as bit masks (deduplicated) over a **14-day window** from the build day plus the previous service day (for its trips after midnight), shapes simplified (Douglas-Peucker, 5 m) and encoded as polylines. Budget: ≤ 5 MB gzip, enforced by the build (a build over budget does not replace the previous output).
3. **Metro stations keep the JS app ids**: each GTFS metro stop is matched to the nearest station of `js/data/metro-network.js` serving the same line within 400 m; unmatched stops become new stations and are reported. No separate topology file is derived: the feed's patterns already describe branches and short turns (e.g. Villa S.G. → Bisceglie on M1), and the hand-written `metro-network.js` stays for the Lite app and as the station reference.
4. **Names**: `tpl_fermate.csv` names for surface stops when available, otherwise the feed name title-cased; Latin-1 mojibake is repaired. Trolleybus lines come from `tpl_orari.csv`.
5. **Not committed.** `data/gtfs/` is git-ignored: the deploy workflow downloads the feed, builds the datasets and publishes them with the site. If the portal is unreachable, the last feed saved in the Actions cache is used; if there is none, the site is deployed without GTFS data and the app uses the synthetic timetable.
6. **Refresh twice a week** (Monday and Thursday) instead of weekly: the window is anchored to the build day, and a new release (published every two to four weeks) is picked up within three or four days. A failed GTFS build never blocks the deploy of the site. GitHub disables scheduled workflows after 60 days without activity in a public repository: the refresh then stops until the workflow is re-enabled (tracked in the roadmap).

## Consequences

- Measured on the real feed (Python 3.10): full-network window (166 routes, 121,799 trips) 26 s, 820 MB of RAM, 0.52 MB gzip; window of 2026-10-10 (67 routes still covered) 15 s, 280 MB, 0.21 MB gzip. Memory grows with the window, fine for GitHub runners (7 GB).
- The repository history does not grow with every refresh; reproducing a past dataset requires the corresponding feed version (kept by the Mobility Database archive).
- The Dart core (F3) reads format v1; any breaking change increments `version` in every file.
