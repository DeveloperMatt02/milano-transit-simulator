"""Build ``js/data/metro-frequencies.js`` from the Comune di Milano metro timetable summary.

Input: ``data/raw/tpl_metroorari.csv`` (one row per *route variant*, i.e. per
branch and direction, and per day type ``L`` weekday / ``S`` Saturday /
``F`` Sunday & holidays). Relevant columns:

* ``corse_gior`` trips in the whole day
* ``corse_punt`` / ``corse_morb`` / ``corse_sera`` trips in the peak, off-peak
  and evening time bands. The dataset does not document the band length; a
  value of two hours reproduces the headways published by ATM, so that is the
  assumption used here (see docs/TECHNICAL_DESIGN.md).
* ``inizio`` / ``fine`` first departure / last arrival of the variant. Times
  after midnight (e.g. ``00:53``) belong to the same service day.

For each line and day type the variants are summed and divided by two
(two directions) to obtain the frequency on the busiest (trunk) section.
"""

from __future__ import annotations

import csv
import sys
from collections import defaultdict
from pathlib import Path

from common import JS_DATA_DIR, RAW_DIR, hhmm_to_minutes, minutes_to_hhmm, to_service_minutes, write_js_constant

BAND_SECONDS = 2 * 3600
DAY_TYPES = ("L", "S", "F")
LINES = ("M1", "M2", "M3", "M4", "M5")

# Used only when a line/day type is missing from the dataset.
FALLBACK = {
    "daily_trips": 250,
    "peak_headway": 180,
    "mid_headway": 300,
    "evening_headway": 480,
    "first_departure": "05:40",
    "last_arrival": "24:30",
}


def headway_seconds(trips_in_band_both_directions: int, default: int, low: int, high: int) -> int:
    """Average interval between trains in one direction during a 2-hour band."""
    per_direction = trips_in_band_both_directions / 2
    if per_direction <= 0:
        return default
    return max(low, min(high, round(BAND_SECONDS / per_direction)))


def aggregate(rows) -> dict:
    """Aggregate CSV rows into ``{line: {day_type: summary}}``."""
    buckets: dict[tuple[str, str], dict] = defaultdict(
        lambda: {"gior": 0, "punt": 0, "morb": 0, "sera": 0, "starts": [], "ends": []}
    )
    for row in rows:
        line_number = (row.get("linea") or "").strip().strip('"')
        line_id = f"M{line_number}"
        day_type = (row.get("tipo_giorno") or "").strip()
        if line_id not in LINES or day_type not in DAY_TYPES:
            continue
        bucket = buckets[(line_id, day_type)]
        try:
            bucket["gior"] += int(row.get("corse_gior") or 0)
            bucket["punt"] += int(row.get("corse_punt") or 0)
            bucket["morb"] += int(row.get("corse_morb") or 0)
            bucket["sera"] += int(row.get("corse_sera") or 0)
        except ValueError:
            continue
        start = hhmm_to_minutes(row.get("inizio") or "")
        end = hhmm_to_minutes(row.get("fine") or "")
        if start is not None:
            bucket["starts"].append(to_service_minutes(start))
        if end is not None:
            bucket["ends"].append(to_service_minutes(end))

    result: dict[str, dict] = {line: {} for line in LINES}
    for (line_id, day_type), b in buckets.items():
        result[line_id][day_type] = {
            "daily_trips": round(b["gior"] / 2),
            "peak_headway": headway_seconds(b["punt"], 180, 90, 600),
            "mid_headway": headway_seconds(b["morb"], 300, 120, 900),
            "evening_headway": headway_seconds(b["sera"], 480, 180, 1200),
            "first_departure": minutes_to_hhmm(min(b["starts"])) if b["starts"] else FALLBACK["first_departure"],
            "last_arrival": minutes_to_hhmm(max(b["ends"])) if b["ends"] else FALLBACK["last_arrival"],
        }
    for line_id in LINES:
        for day_type in DAY_TYPES:
            if day_type not in result[line_id]:
                print(f"  ! {line_id}/{day_type} missing from dataset, using fallback values")
                result[line_id][day_type] = dict(FALLBACK)
    return result


def read_rows(path: Path):
    with open(path, encoding="utf-8") as handle:
        sample = handle.read(2048)
        handle.seek(0)
        yield from csv.DictReader(handle, delimiter=";" if ";" in sample else ",")


def main() -> int:
    source = RAW_DIR / "tpl_metroorari.csv"
    if not source.exists():
        print(f"Missing {source}. Run: python scripts/download_open_data.py", file=sys.stderr)
        return 1
    frequencies = aggregate(read_rows(source))
    for line_id, days in frequencies.items():
        weekday = days["L"]
        print(
            f"  {line_id}: peak {weekday['peak_headway']}s, off-peak {weekday['mid_headway']}s, "
            f"evening {weekday['evening_headway']}s, {weekday['first_departure']}-{weekday['last_arrival']}"
        )
    write_js_constant(
        JS_DATA_DIR / "metro-frequencies.js",
        "METRO_OFFICIAL_FREQUENCIES",
        frequencies,
        "Milan metro service levels per line and day type (L weekday, S Saturday, F Sunday/holiday), "
        "derived from Comune di Milano open data (CC BY 4.0).",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
