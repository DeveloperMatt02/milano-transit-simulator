"""Build ``js/data/surface-network.js`` (trams, trolleybuses and buses).

Inputs (Comune di Milano open data, CC BY 4.0, see download_open_data.py):

* ``tpl_fermate.csv``  stop id, description and WGS84 coordinates
* ``tpl_sequenza.csv`` ordered list of stops for every route variant (*percorso*)
* ``tpl_orari.csv``    per route variant and day type: number of trips per time
                       band, first and last run

Output schema (compact JSON)::

    {
      "stations": {"<stop id>": {"id", "name", "lat", "lon"}},
      "lines": {
        "<line id>": {
          "id", "type": "TRAM" | "FILOBUS" | "BUS", "color",
          "percorsi": {
            "<route id>": {
              "id", "stops": ["<stop id>", ...],
              "frequencies": {"L" | "S" | "F": {daily_trips, peak_headway, mid_headway,
                                                 evening_headway, service_start, service_end}}
            }
          }
        }
      }
    }

``service_start`` / ``service_end`` use the service-day convention (values after
midnight are >= 24:00). A day type is absent when the route does not run that day.
"""

from __future__ import annotations

import csv
import sys

from common import JS_DATA_DIR, RAW_DIR, hhmm_to_minutes, minutes_to_hhmm, to_service_minutes, write_js_constant

BAND_SECONDS = 2 * 3600
DAY_TYPES = ("L", "S", "F")
MODE_COLORS = {"TRAM": "#FF9500", "FILOBUS": "#00C753", "BUS": "#007AFF"}
SERVICE_DAY_START = 3 * 60
SERVICE_DAY_END = 27 * 60


def headway(trips_in_band: int, default: int, low: int, high: int) -> int:
    if trips_in_band <= 0:
        return default
    return max(low, min(high, round(BAND_SECONDS / trips_in_band)))


def service_window(start: str, end: str, daily_trips: int) -> tuple[int, int] | None:
    """Return (start, end) in service-day minutes, handling night and 24-hour routes."""
    start_min, end_min = hhmm_to_minutes(start), hhmm_to_minutes(end)
    if start_min is None or end_min is None:
        return None
    clock_span = (end_min - start_min) % (24 * 60)
    # 24-hour routes (e.g. circular lines 90/91) report nearly identical first and last run.
    if clock_span < 60 and daily_trips > 10:
        return SERVICE_DAY_START, SERVICE_DAY_END
    service_start = to_service_minutes(start_min)
    return service_start, service_start + clock_span


def read_csv(path):
    with open(path, encoding="utf-8") as handle:
        yield from csv.DictReader(handle, delimiter=";")


def main() -> int:
    paths = {name: RAW_DIR / f"{name}.csv" for name in ("tpl_fermate", "tpl_sequenza", "tpl_orari")}
    missing = [str(p) for p in paths.values() if not p.exists()]
    if missing:
        print(f"Missing {', '.join(missing)}. Run: python scripts/download_open_data.py", file=sys.stderr)
        return 1

    stops = {}
    for row in read_csv(paths["tpl_fermate"]):
        stop_id = (row.get("id_amat") or "").strip()
        try:
            lon = float((row.get("LONG_X_4326") or "").replace(",", "."))
            lat = float((row.get("LAT_Y_4326") or "").replace(",", "."))
        except ValueError:
            continue
        if stop_id:
            stops[stop_id] = {"id": stop_id, "name": (row.get("ubicazione") or "").strip(), "lat": round(lat, 6), "lon": round(lon, 6)}
    print(f"Loaded {len(stops)} stops")

    sequences: dict[str, list[tuple[int, str]]] = {}
    for row in read_csv(paths["tpl_sequenza"]):
        try:
            sequences.setdefault(row["percorso"], []).append((int(row["num"]), row["id_ferm"]))
        except (KeyError, TypeError, ValueError):
            continue
    ordered = {route: [stop for _, stop in sorted(items)] for route, items in sequences.items()}
    print(f"Loaded {len(ordered)} route sequences")

    lines: dict[str, dict] = {}
    used_stops: set[str] = set()
    skipped_unknown_stops = 0
    for row in read_csv(paths["tpl_orari"]):
        line_id = (row.get("linea") or "").strip()
        mode = (row.get("mezzo") or "").strip().upper()
        route_id = (row.get("percorso") or "").strip()
        day_type = (row.get("tipo_giorno") or "").strip()
        if not line_id or not route_id or day_type not in DAY_TYPES or route_id not in ordered:
            continue
        route_stops = [s for s in ordered[route_id] if s in stops]
        skipped_unknown_stops += len(ordered[route_id]) - len(route_stops)
        if len(route_stops) < 2:
            continue
        try:
            trips = {k: int(row.get(k) or 0) for k in ("corse_gior", "corse_punt", "corse_morb", "corse_sera")}
        except ValueError:
            continue
        window = service_window(row.get("inizio") or "", row.get("fine") or "", trips["corse_gior"])
        if window is None or trips["corse_gior"] == 0:
            continue

        line = lines.setdefault(line_id, {"id": line_id, "type": mode, "color": MODE_COLORS.get(mode, "#8E8E93"), "percorsi": {}})
        route = line["percorsi"].setdefault(route_id, {"id": route_id, "stops": route_stops, "frequencies": {}})
        used_stops.update(route_stops)
        route["frequencies"][day_type] = {
            "daily_trips": trips["corse_gior"],
            "peak_headway": headway(trips["corse_punt"], 600, 180, 1200),
            "mid_headway": headway(trips["corse_morb"], 900, 240, 1800),
            "evening_headway": headway(trips["corse_sera"], 1200, 300, 2400),
            "service_start": minutes_to_hhmm(window[0]),
            "service_end": minutes_to_hhmm(window[1]),
        }

    network = {
        "stations": {stop_id: stops[stop_id] for stop_id in sorted(used_stops, key=lambda s: int(s) if s.isdigit() else s)},
        "lines": lines,
    }
    print(f"Lines: {len(lines)}, stops in use: {len(used_stops)}, unknown stop references dropped: {skipped_unknown_stops}")
    write_js_constant(
        JS_DATA_DIR / "surface-network.js",
        "SURFACE_NETWORK",
        network,
        "Milan surface network (tram, trolleybus, bus) derived from Comune di Milano open data (CC BY 4.0).",
        compact=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
