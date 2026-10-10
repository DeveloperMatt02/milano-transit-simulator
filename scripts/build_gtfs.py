"""Build the GTFS datasets ``data/gtfs/*.json`` from the city's GTFS feed.

Input: ``data/raw/gtfs.zip`` (Comune di Milano / AMAT, CC BY; see download_open_data.py),
or an extracted feed directory. Optional helpers from the older open data, when present:
``tpl_fermate.csv`` (readable stop names) and ``tpl_orari.csv`` (which surface lines are
trolleybuses). ``js/data/metro-network.js`` is the reference for metro station ids, so the
stations keep the same ids as in the JS app.

The feed weighs ~400 MB unzipped, almost all of it ``stop_times.txt``. The output keeps
only the service days of a rolling window (default: today + 14 days, plus the previous
service day for its trips after midnight) and stores the
timetable compactly:

* a *pattern* is a route + headsign + ordered list of stops (+ shape);
* a *profile* is a pattern + the arrival offsets and dwell times shared by many trips;
* a *trip* is ``(profile, start time, service)``; a service is a bit mask over the window.

Output files (format version 1, documented in docs/TECHNICAL_DESIGN.md §9):

* ``network.json``   stops, metro stations, routes (with ``coverage_end``), patterns
* ``timetable.json`` window, services, profiles, trips (columnar)
* ``shapes.json``    simplified route geometry as encoded polylines
* ``meta.json``      feed version and validity, counts, warnings, attribution

``coverage_end`` is the last date for which the feed has trips of that route. The feed
expires by mode at different dates (e.g. surface lines before the metro), so the app
decides route by route and day by day whether to use these times or the synthetic
scheduler (ADR 0002).

Usage::

    python scripts/build_gtfs.py                       # window starts today (Europe/Rome)
    python scripts/build_gtfs.py --start 2026-10-05 --days 14 --out data/gtfs
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import gzip
import io
import json
import math
import re
import shutil
import sys
import tempfile
import unicodedata
import zipfile
from collections import defaultdict
from pathlib import Path

from common import JS_DATA_DIR, RAW_DIR, REPO_ROOT, read_js_constant

FORMAT_VERSION = 1
DEFAULT_DAYS = 14
DEFAULT_BUDGET_MB = 5
SHAPE_TOLERANCE_M = 5.0
METRO_MATCH_M = 400.0
OUT_DIR = REPO_ROOT / "data" / "gtfs"
ATTRIBUTION = "Timetables: Comune di Milano / AMAT, GTFS feed (CC BY)"

MODE_ORDER = {"METRO": 0, "TRAM": 1, "FILOBUS": 2, "BUS": 3}
OUTPUT_FILES = ("network", "timetable", "shapes", "meta")


class BudgetExceeded(Exception):
    """The compressed output is larger than the size budget."""


# --------------------------------------------------------------------------- reading


class GtfsSource:
    """Read-only access to a GTFS feed stored as a zip archive or as a directory."""

    def __init__(self, path):
        self.path = Path(path)
        self._zip = zipfile.ZipFile(self.path) if self.path.is_file() else None

    def has(self, name: str) -> bool:
        if self._zip is not None:
            return name in self._zip.namelist()
        return (self.path / name).exists()

    def _open(self, name: str):
        if self._zip is not None:
            return io.TextIOWrapper(self._zip.open(name), encoding="utf-8-sig", newline="")
        return open(self.path / name, encoding="utf-8-sig", newline="")

    def rows(self, name: str):
        """Rows of a feed file as dicts (empty iterator when the file is missing)."""
        if not self.has(name):
            return
        with self._open(name) as handle:
            yield from csv.DictReader(handle)

    def table(self, name: str):
        """(header index, row iterator of lists) for large files, faster than DictReader."""
        handle = self._open(name)
        reader = csv.reader(handle)
        header = next(reader)
        return {column.strip(): i for i, column in enumerate(header)}, reader, handle


_TIME = re.compile(r"^(\d{1,3}):([0-5]\d):([0-5]\d)$")


def parse_gtfs_time(value: str) -> int:
    """GTFS ``H:MM:SS`` (hours may exceed 23) -> seconds after the service date's midnight."""
    match = _TIME.match(value.strip()) if isinstance(value, str) else None
    if not match:
        raise ValueError(f"invalid GTFS time {value!r}")
    return int(match.group(1)) * 3600 + int(match.group(2)) * 60 + int(match.group(3))


def parse_date(value: str) -> dt.date:
    return dt.datetime.strptime(value.strip(), "%Y%m%d").date()


def window_dates(start: dt.date, days: int) -> list[dt.date]:
    return [start + dt.timedelta(days=i) for i in range(days)]


def service_dates(source: GtfsSource) -> dict[str, set[dt.date]]:
    """Dates on which each service runs, from calendar.txt and calendar_dates.txt."""
    dates: dict[str, set[dt.date]] = defaultdict(set)
    weekdays = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    for row in source.rows("calendar.txt"):
        day, end = parse_date(row["start_date"]), parse_date(row["end_date"])
        runs = [row.get(name, "0").strip() == "1" for name in weekdays]
        while day <= end:
            if runs[day.weekday()]:
                dates[row["service_id"]].add(day)
            day += dt.timedelta(days=1)
    for row in source.rows("calendar_dates.txt"):
        day = parse_date(row["date"])
        if row["exception_type"].strip() == "1":
            dates[row["service_id"]].add(day)
        elif row["exception_type"].strip() == "2":
            dates[row["service_id"]].discard(day)
    return dict(dates)


def service_masks(dates: dict[str, set[dt.date]], window: list[dt.date]) -> dict[str, int]:
    """Bit mask of the window days on which each service runs (services with no day are left out)."""
    index = {day: i for i, day in enumerate(window)}
    masks = {}
    for service_id, days in dates.items():
        mask = 0
        for day in days:
            if day in index:
                mask |= 1 << index[day]
        if mask:
            masks[service_id] = mask
    return masks


def feed_start(source: GtfsSource) -> dt.date:
    """Start date declared by feed_info.txt, or the first service date."""
    for row in source.rows("feed_info.txt"):
        if row.get("feed_start_date"):
            return parse_date(row["feed_start_date"])
    all_days = [day for days in service_dates(source).values() for day in days]
    if not all_days:
        raise ValueError("the feed defines no service dates")
    return min(all_days)


# --------------------------------------------------------------------------- names


_ABBREVIATIONS = {"p.le", "v.le", "l.go", "p.za", "p.zza", "c.so", "p.ta", "v.lo", "s.da", "f.lli", "staz.", "naz."}
_UPPER = {"fs", "fn", "m1", "m2", "m3", "m4", "m5", "qt8", "rfi", "atm", "ii", "iii", "iv", "xx", "xxv"}
_LOWER = {"di", "da", "de", "del", "dei", "degli", "della", "delle", "dello", "e", "al", "alla", "ai", "in", "per", "con", "su", "sul", "sulla", "a"}


def repair_text(value: str) -> str:
    """Undo UTF-8 text decoded as Latin-1/CP1252 upstream ("libertÃ\xa0" -> "libertà")."""
    if not value or not any(ch in value for ch in "ÃÂ"):
        return value
    for codec in ("cp1252", "latin-1"):
        try:
            return value.encode(codec).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
    return value


def _capitalise(core: str) -> str:
    # Capitalise every alphabetic segment between ".", "-", "/" and apostrophes: s.agostino -> S.Agostino.
    parts = re.split(r"([.\-'’/])", core)
    return "".join(p[:1].upper() + p[1:] if p and p[0].isalpha() else p for p in parts)


def prettify_name(value: str) -> str:
    """Title-case a lower/upper-case feed name, keeping abbreviations and line codes readable."""
    words = repair_text(value).strip().lower().split()
    out = []
    for i, word in enumerate(words):
        prefix = re.match(r"^[(\"]*", word).group(0)
        suffix = re.search(r"[)\",;:]*$", word[len(prefix):]).group(0)
        core = word[len(prefix): len(word) - len(suffix)] if suffix else word[len(prefix):]
        if core in _UPPER:
            core = core.upper()
        elif core in _ABBREVIATIONS:
            core = core[:1].upper() + core[1:]
        elif core in _LOWER and i > 0 and not prefix:
            pass
        else:
            core = _capitalise(core)
        out.append(prefix + core + suffix)
    return " ".join(out)


def slugify(value: str) -> str:
    ascii_name = unicodedata.normalize("NFD", value).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "_", ascii_name).strip("_")


def natural_key(value: str):
    return [(0, int(part), "") if part.isdigit() else (1, 0, part.lower()) for part in re.split(r"(\d+)", value) if part]


# --------------------------------------------------------------------------- geometry


def distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Equirectangular distance in metres (accurate enough at city scale)."""
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6371e3 * math.hypot(x, y)


def simplify(points: list[tuple[float, float]], tolerance_m: float = SHAPE_TOLERANCE_M) -> list[tuple[float, float]]:
    """Douglas-Peucker simplification of (lat, lon) points; endpoints are always kept."""
    if len(points) < 3:
        return list(points)
    lat0 = math.radians(points[0][0])
    k = 6371e3 * math.pi / 180
    xy = [((lon - points[0][1]) * k * math.cos(lat0), (lat - points[0][0]) * k) for lat, lon in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (ax, ay), (bx, by) = xy[first], xy[last]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, worst_i = 0.0, -1
        for i in range(first + 1, last):
            px, py = xy[i]
            if length == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (length * length)))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if d > worst:
                worst, worst_i = d, i
        if worst > tolerance_m:
            keep[worst_i] = True
            stack.append((first, worst_i))
            stack.append((worst_i, last))
    return [p for p, k_ in zip(points, keep) if k_]


def encode_polyline(points: list[tuple[float, float]], precision: int = 5) -> str:
    """Google encoded polyline algorithm."""
    factor = 10**precision
    out, prev_lat, prev_lon = [], 0, 0
    for lat, lon in points:
        ilat, ilon = round(lat * factor), round(lon * factor)
        for delta in (ilat - prev_lat, ilon - prev_lon):
            value = ~(delta << 1) if delta < 0 else delta << 1
            while value >= 0x20:
                out.append(chr((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            out.append(chr(value + 63))
        prev_lat, prev_lon = ilat, ilon
    return "".join(out)


def decode_polyline(encoded: str, precision: int = 5) -> list[tuple[float, float]]:
    factor = 10**precision
    points, index, lat, lon = [], 0, 0, 0
    while index < len(encoded):
        for coordinate in range(2):
            shift, result = 0, 0
            while True:
                byte = ord(encoded[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if coordinate == 0:
                lat += delta
            else:
                lon += delta
        points.append((lat / factor, lon / factor))
    return points


# --------------------------------------------------------------------------- metro stations


_METRO_SUFFIX = re.compile(r"\s+M[1-9](\s+M[1-9])*$", re.IGNORECASE)


def match_metro_stations(stops, stop_lines, reference, max_distance_m: float = METRO_MATCH_M):
    """Map GTFS metro stops to the stations of the reference network.

    Each stop goes to the nearest reference station that serves one of its lines, if it is
    closer than ``max_distance_m``; platforms of one interchange (``LORETO M1``, ``LORETO M2``)
    therefore end up in the same station. Stops without a match become new stations (e.g. a
    line extension) and are reported in ``warnings``.

    :param stops: ``{stop_id: (lat, lon, name)}``
    :param stop_lines: ``{stop_id: {"M1", ...}}``
    :param reference: METRO_NETWORK-like dict, or None
    :returns: ``(mapping stop_id -> station id, new stations {id: {id, name}}, warnings)``
    """
    ref = (reference or {}).get("stations", {})
    mapping, new, warnings = {}, {}, []
    first_position: dict[str, tuple[float, float]] = {}
    for stop_id in sorted(stops, key=natural_key):
        lat, lon, name = stops[stop_id]
        lines = stop_lines.get(stop_id, set())
        best = None
        for station_id, station in ref.items():
            if lines and not lines & set(station.get("lines", [])):
                continue
            d = distance_m(lat, lon, station["lat"], station["lon"])
            if best is None or d < best[0]:
                best = (d, station_id)
        if best is not None and best[0] <= max_distance_m:
            mapping[stop_id] = best[1]
            continue
        base = _METRO_SUFFIX.sub("", name.strip())
        slug = slugify(base)
        far = slug in first_position and distance_m(lat, lon, *first_position[slug]) > max_distance_m
        if slug in ref or far:
            slug = "_".join([slug] + sorted(line.lower() for line in lines))
        first_position.setdefault(slug, (lat, lon))
        mapping[stop_id] = slug
        new.setdefault(slug, {"id": slug, "name": prettify_name(base)})
        if ref:
            warnings.append(
                f"metro stop {stop_id!r} ({name}, lines {', '.join(sorted(lines)) or '?'}) has no reference station "
                f"within {max_distance_m:.0f} m: new station {slug!r}"
            )
    return mapping, new, warnings


# --------------------------------------------------------------------------- build


def _interpolate(rows):
    """Fills stops without times linearly (by position) between the surrounding timed stops."""
    out, filled = list(rows), 0
    timed = [i for i, r in enumerate(rows) if r[1] is not None]
    for a, b in zip(timed, timed[1:]):
        start, end = rows[a][2], rows[b][1]
        for i in range(a + 1, b):
            t = round(start + (end - start) * (i - a) / (b - a))
            out[i] = (rows[i][0], t, t, rows[i][3])
            filled += 1
    return out, filled


def _route_mode(row: dict, line_modes: dict) -> str:
    route_type = row.get("route_type", "").strip()
    if route_type == "1":
        return "METRO"
    if route_type in ("0", "900"):
        return "TRAM"
    if route_type in ("11", "800"):
        return "FILOBUS"
    return "FILOBUS" if line_modes.get(row.get("route_short_name", "").strip()) == "FILOBUS" else "BUS"


def _route_name(row: dict, mode: str) -> str:
    if mode == "METRO":
        return row["route_id"].strip()
    return row.get("route_short_name", "").strip() or row["route_id"].strip()


def build(source: GtfsSource, start: dt.date, days: int = DEFAULT_DAYS, *, metro_reference=None,
          stop_names=None, line_modes=None, built_at: str | None = None) -> dict:
    """Builds the four output documents in memory (deterministic except ``meta.built_at``)."""
    stop_names = stop_names or {}
    line_modes = line_modes or {}
    warnings: list[str] = []
    window = window_dates(start, days)
    dates = service_dates(source)
    masks = service_masks(dates, window)
    last_date = {service_id: max(days_) for service_id, days_ in dates.items() if days_}

    routes = {row["route_id"]: row for row in source.rows("routes.txt")}
    modes = {route_id: _route_mode(row, line_modes) for route_id, row in routes.items()}

    # Trips: coverage end per route over the whole feed, details of the trips inside the window.
    coverage_end: dict[str, dt.date] = {}
    active: dict[str, tuple] = {}
    unknown_routes = 0
    for row in source.rows("trips.txt"):
        route_id, service_id = row["route_id"], row["service_id"]
        if route_id not in routes:
            unknown_routes += 1
            continue
        end = last_date.get(service_id)
        if end and (route_id not in coverage_end or end > coverage_end[route_id]):
            coverage_end[route_id] = end
        if service_id in masks:
            headsign = prettify_name(row.get("trip_headsign", "") or "")
            active[row["trip_id"]] = (route_id, service_id, headsign, (row.get("shape_id") or "").strip() or None)

    if unknown_routes:
        warnings.append(f"{unknown_routes} trips reference a route missing from routes.txt and were skipped")

    # stop_times: rows of a trip may be scattered through the file (they are in the real feed)
    # and out of stop_sequence order, so rows are collected per trip — for window trips only.
    trips = []  # (profile key, start, service)
    inconsistent = 0
    rows_by_trip: dict[str, list] = defaultdict(list)
    header, reader, handle = source.table("stop_times.txt")
    i_trip, i_arr, i_dep, i_stop, i_seq = (header[c] for c in ("trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"))
    try:
        for record in reader:
            trip_id = record[i_trip]
            if trip_id in active:
                # Non-timepoint stops may leave both times empty: interpolated below.
                arr_text, dep_text = record[i_arr].strip(), record[i_dep].strip()
                arrival = parse_gtfs_time(arr_text or dep_text) if (arr_text or dep_text) else None
                departure = parse_gtfs_time(dep_text or arr_text) if (arr_text or dep_text) else None
                rows_by_trip[trip_id].append((int(record[i_seq]), arrival, departure, record[i_stop].strip()))
    finally:
        handle.close()

    duplicates = interpolated = untimed = 0
    for trip_id in sorted(rows_by_trip):
        rows = sorted(rows_by_trip.pop(trip_id), key=lambda r: r[0])
        unique = [r for i, r in enumerate(rows) if i == 0 or r[0] != rows[i - 1][0]]
        duplicates += len(rows) - len(unique)
        rows = unique
        if rows[0][1] is None or rows[-1][1] is None:
            untimed += 1  # GTFS requires times at the first and last stop
            continue
        rows, filled = _interpolate(rows)
        interpolated += filled
        route_id, service_id, headsign, shape_id = active[trip_id]
        start_time = rows[0][1]
        arrivals, dwells, previous = [], [], start_time
        for _, arrival, departure, _ in rows:
            if arrival < previous or departure < arrival:
                inconsistent += 1
                arrival = max(arrival, previous)
                departure = max(departure, arrival)
            arrivals.append(arrival - start_time)
            dwells.append(departure - arrival)
            previous = departure
        pattern = (route_id, headsign, tuple(r[3] for r in rows), shape_id)
        trips.append(((pattern, tuple(arrivals), tuple(dwells)), start_time, service_id))
    if inconsistent:
        warnings.append(f"{inconsistent} stop times were not monotonic and were clamped")
    if duplicates:
        warnings.append(f"{duplicates} stop times repeated a stop_sequence of their trip and were dropped")
    if interpolated:
        warnings.append(f"{interpolated} stop times without times were interpolated")
    if untimed:
        warnings.append(f"{untimed} trips have no time at the first or last stop and were skipped")
    missing_times = len(active) - len(trips) - untimed
    if missing_times:
        warnings.append(f"{missing_times} trips in the window have no stop times")

    # Stops and metro stations.
    patterns_used = {key[0] for key, _, _ in trips}
    used_stops = {stop_id for p in patterns_used for stop_id in p[2]}
    metro_stop_lines: dict[str, set] = defaultdict(set)
    for route_id, _, stop_ids, _ in patterns_used:
        if modes.get(route_id) == "METRO":
            for stop_id in stop_ids:
                metro_stop_lines[stop_id].add(_route_name(routes[route_id], "METRO"))
    stop_rows = {row["stop_id"].strip(): row for row in source.rows("stops.txt") if row["stop_id"].strip() in used_stops}
    missing_stops = used_stops - set(stop_rows)
    if missing_stops:
        raise ValueError(f"stop_times.txt references unknown stops: {sorted(missing_stops)[:10]}")

    metro_stops = {
        stop_id: (float(stop_rows[stop_id]["stop_lat"]), float(stop_rows[stop_id]["stop_lon"]), stop_rows[stop_id]["stop_name"])
        for stop_id in metro_stop_lines
    }
    station_of, new_stations, station_warnings = match_metro_stations(metro_stops, metro_stop_lines, metro_reference)
    warnings.extend(station_warnings)
    reference_stations = (metro_reference or {}).get("stations", {})

    def station_name(station_id):
        if station_id in reference_stations:
            return reference_stations[station_id]["name"]
        return new_stations[station_id]["name"]

    stop_ids = sorted(used_stops, key=natural_key)
    stop_index = {stop_id: i for i, stop_id in enumerate(stop_ids)}
    stops_out = []
    for stop_id in stop_ids:
        row = stop_rows[stop_id]
        station = station_of.get(stop_id)
        if station:
            name = station_name(station)
        else:
            name = repair_text(stop_names.get(stop_id, "")) or prettify_name(row["stop_name"])
        wheelchair = (row.get("wheelchair_boarding") or "").strip()
        stops_out.append({
            "id": stop_id,
            "name": name,
            "lat": round(float(row["stop_lat"]), 6),
            "lon": round(float(row["stop_lon"]), 6),
            "wheelchair": int(wheelchair) if wheelchair.isdigit() else 0,
            "station": station,
        })

    stations = {}
    for stop_id, station_id in station_of.items():
        entry = stations.setdefault(station_id, {"id": station_id, "name": station_name(station_id), "lines": set(), "stops": []})
        entry["lines"] |= metro_stop_lines[stop_id]
        entry["stops"].append(stop_index[stop_id])
    stations_out = []
    for station_id in sorted(stations):
        entry = stations[station_id]
        if station_id in reference_stations:
            lat, lon = reference_stations[station_id]["lat"], reference_stations[station_id]["lon"]
        else:
            lat = sum(stops_out[i]["lat"] for i in entry["stops"]) / len(entry["stops"])
            lon = sum(stops_out[i]["lon"] for i in entry["stops"]) / len(entry["stops"])
        stations_out.append({
            "id": station_id,
            "name": entry["name"],
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "lines": sorted(entry["lines"], key=natural_key),
            "stops": sorted(entry["stops"]),
        })

    # Routes, shapes, patterns, profiles, services, trips — all in a deterministic order.
    route_ids = sorted({p[0] for p in patterns_used}, key=lambda r: (MODE_ORDER[modes[r]], natural_key(_route_name(routes[r], modes[r]))))
    route_index = {route_id: i for i, route_id in enumerate(route_ids)}
    routes_out = []
    for route_id in route_ids:
        row, mode = routes[route_id], modes[route_id]
        color = (row.get("route_color") or "").strip()
        routes_out.append({
            "id": route_id,
            "name": _route_name(row, mode),
            "long_name": prettify_name(row.get("route_long_name", "") or ""),
            "mode": mode,
            "color": f"#{color.upper()}" if re.fullmatch(r"[0-9A-Fa-f]{6}", color) else None,
            "coverage_end": coverage_end[route_id].isoformat() if route_id in coverage_end else None,
        })

    shape_ids = sorted({p[3] for p in patterns_used if p[3]}, key=natural_key)
    shape_index = {shape_id: i for i, shape_id in enumerate(shape_ids)}
    shape_points: dict[str, list] = defaultdict(list)
    for row in source.rows("shapes.txt"):
        shape_id = row["shape_id"].strip()
        if shape_id in shape_index:
            shape_points[shape_id].append((int(row["shape_pt_sequence"]), float(row["shape_pt_lat"]), float(row["shape_pt_lon"])))
    shapes_out, raw_points, kept_points = [], 0, 0
    for shape_id in shape_ids:
        points = [(lat, lon) for _, lat, lon in sorted(shape_points.get(shape_id, []))]
        if not points:
            warnings.append(f"shape {shape_id!r} has no points")
        simplified = simplify(points)
        raw_points += len(points)
        kept_points += len(simplified)
        shapes_out.append(encode_polyline(simplified))

    def pattern_sort_key(p):
        return (route_index[p[0]], [stop_index[s] for s in p[2]], p[1], shape_index.get(p[3], -1))

    patterns = sorted(patterns_used, key=pattern_sort_key)
    pattern_index = {p: i for i, p in enumerate(patterns)}
    patterns_out = [
        {
            "route": route_index[p[0]],
            "headsign": p[1],
            "stops": [stop_index[s] for s in p[2]],
            "shape": shape_index.get(p[3]) if p[3] else None,
        }
        for p in patterns
    ]

    profiles = sorted({key for key, _, _ in trips}, key=lambda k: (pattern_index[k[0]], k[1], k[2]))
    profile_index = {k: i for i, k in enumerate(profiles)}
    profiles_out = []
    for pattern, arrivals, dwells in profiles:
        entry = {"pattern": pattern_index[pattern], "arrivals": list(arrivals)}
        if any(dwells):
            entry["dwells"] = list(dwells)
        profiles_out.append(entry)

    # Many services share the same days inside the window: store each distinct mask once.
    unique_masks = sorted({masks[service_id] for _, _, service_id in trips})
    mask_index = {mask: i for i, mask in enumerate(unique_masks)}
    rows_out = sorted((t[1], profile_index[t[0]], mask_index[masks[t[2]]]) for t in trips)

    feed = next(iter(source.rows("feed_info.txt")), {})

    def feed_date(name):
        value = (feed.get(name) or "").strip()
        return parse_date(value).isoformat() if value else None

    all_dates = [day for days_ in dates.values() for day in days_]
    meta = {
        "version": FORMAT_VERSION,
        "feed": {
            "publisher": feed.get("feed_publisher_name"),
            "version": feed.get("feed_version"),
            "start_date": feed_date("feed_start_date"),
            "end_dates": {"surface": feed_date("surface_end_date"), "metro": feed_date("mm_end_date")},
            "last_service_date": max(all_dates).isoformat() if all_dates else None,
        },
        "window": {"start": start.isoformat(), "days": days},
        "built_at": built_at or dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "counts": {
            "routes": len(routes_out),
            "stops": len(stops_out),
            "stations": len(stations_out),
            "patterns": len(patterns_out),
            "profiles": len(profiles_out),
            "trips": len(rows_out),
            "shapes": len(shapes_out),
            "shape_points": {"raw": raw_points, "kept": kept_points},
        },
        "warnings": warnings,
        "attribution": ATTRIBUTION,
    }
    return {
        "network": {"version": FORMAT_VERSION, "stops": stops_out, "stations": stations_out, "routes": routes_out, "patterns": patterns_out},
        "timetable": {
            "version": FORMAT_VERSION,
            "window": {"start": start.isoformat(), "days": days},
            "services": unique_masks,
            "profiles": profiles_out,
            "trips": {"start": [r[0] for r in rows_out], "profile": [r[1] for r in rows_out], "service": [r[2] for r in rows_out]},
        },
        "shapes": {"version": FORMAT_VERSION, "precision": 5, "shapes": shapes_out},
        "meta": meta,
    }


# --------------------------------------------------------------------------- output


def dumps(document) -> str:
    return json.dumps(document, ensure_ascii=False, separators=(",", ":"))


def write_outputs(outputs: dict, out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for name in OUTPUT_FILES:
        path = out_dir / f"{name}.json"
        path.write_text(dumps(outputs[name]) + "\n", encoding="utf-8")
        paths.append(path)
    return paths


def check_size_budget(paths, budget_bytes: int) -> int:
    """Total gzip size of the files; raises BudgetExceeded above ``budget_bytes``."""
    total = sum(len(gzip.compress(Path(p).read_bytes(), compresslevel=9, mtime=0)) for p in paths)
    if total > budget_bytes:
        raise BudgetExceeded(f"compressed size {total:,} B exceeds the budget of {budget_bytes:,} B")
    return total


def load_metro_reference(path: Path) -> dict:
    return read_js_constant(path)


def load_stop_names(path: Path) -> dict:
    """Readable stop names from tpl_fermate.csv (``id_amat`` equals the GTFS ``stop_id``)."""
    if not path.exists():
        return {}
    with open(path, encoding="utf-8-sig") as handle:
        return {
            (row.get("id_amat") or "").strip(): (row.get("ubicazione") or "").strip()
            for row in csv.DictReader(handle, delimiter=";")
            if (row.get("id_amat") or "").strip() and (row.get("ubicazione") or "").strip()
        }


def load_line_modes(path: Path) -> dict:
    """Surface line -> TRAM / FILOBUS / BUS from tpl_orari.csv (GTFS has no trolleybus type here)."""
    if not path.exists():
        return {}
    with open(path, encoding="utf-8-sig") as handle:
        return {
            (row.get("linea") or "").strip(): (row.get("mezzo") or "").strip().upper()
            for row in csv.DictReader(handle, delimiter=";")
            if (row.get("linea") or "").strip()
        }


def today_in_milan() -> dt.date:
    try:
        from zoneinfo import ZoneInfo

        return dt.datetime.now(ZoneInfo("Europe/Rome")).date()
    except Exception:  # noqa: BLE001 - tzdata missing: UTC is at most one day off
        return dt.datetime.now(dt.timezone.utc).date()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--gtfs", type=Path, default=RAW_DIR / "gtfs.zip", help="feed zip or directory")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="output directory")
    parser.add_argument("--start", type=dt.date.fromisoformat, default=None, help="first day to cover (default: today in Milan); the window starts the day before")
    parser.add_argument("--days", type=int, default=DEFAULT_DAYS, help="days covered from --start (the previous service day is added)")
    parser.add_argument("--budget-mb", type=float, default=DEFAULT_BUDGET_MB, help="maximum gzip size of the output")
    args = parser.parse_args(argv)
    if args.days < 1:
        parser.error("--days must be at least 1")

    if not args.gtfs.exists():
        print(f"Missing {args.gtfs}. Download it with: python scripts/download_open_data.py --gtfs", file=sys.stderr)
        return 1
    first_day = args.start or today_in_milan()
    # The window also includes the previous service day, whose trips after midnight
    # (times >= 24:00) are still running in the early hours of the first day.
    start = first_day - dt.timedelta(days=1)
    print(f"Building GTFS datasets from {args.gtfs} for {first_day} + {args.days} days (window from {start})…")
    outputs = build(
        GtfsSource(args.gtfs),
        start,
        args.days + 1,
        metro_reference=load_metro_reference(JS_DATA_DIR / "metro-network.js"),
        stop_names=load_stop_names(RAW_DIR / "tpl_fermate.csv"),
        line_modes=load_line_modes(RAW_DIR / "tpl_orari.csv"),
    )
    meta = outputs["meta"]
    for warning in meta["warnings"]:
        print(f"  ! {warning}")
    print("  " + ", ".join(f"{k}: {v:,}" for k, v in meta["counts"].items() if isinstance(v, int)))
    if not meta["counts"]["trips"]:
        print("  ! no trips in the window: the app will use the synthetic timetable", file=sys.stderr)

    # Write to a temporary directory and replace the output only if the budget is met,
    # so a bad build never overwrites the last good dataset.
    with tempfile.TemporaryDirectory() as tmp:
        paths = write_outputs(outputs, Path(tmp))
        try:
            total = check_size_budget(paths, int(args.budget_mb * 1024 * 1024))
        except BudgetExceeded as error:
            print(f"  ✗ {error}", file=sys.stderr)
            return 2
        args.out.mkdir(parents=True, exist_ok=True)
        for path in paths:
            shutil.copyfile(path, args.out / path.name)
            print(f"  ✓ {args.out / path.name} ({path.stat().st_size:,} B)")
    print(f"  ✓ total gzip size {total / 1024 / 1024:.2f} MB (budget {args.budget_mb} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
