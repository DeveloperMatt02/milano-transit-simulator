"""Builds the GTFS fixture used by the Dart tests from the Python mini feed.

    python3 packages/transit_core/tool/make_fixtures.py          # rewrite
    python3 packages/transit_core/tool/make_fixtures.py --check  # exit 1 if out of date

Input: tests/python/fixtures/gtfs_mini (see its README); window 2026-10-05 + 7 days, the same
metro reference stations as tests/python/test_gtfs.py. Output:
packages/transit_core/test/fixtures/gtfs_mini/{network,timetable,shapes,meta}.json.
"""

import datetime as dt
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts"))

import build_gtfs as g  # noqa: E402

SOURCE = REPO / "tests" / "python" / "fixtures" / "gtfs_mini"
OUT = REPO / "packages" / "transit_core" / "test" / "fixtures" / "gtfs_mini"
REFERENCE = {
    "stations": {
        "alfa": {"id": "alfa", "name": "Alfa", "lat": 45.4601, "lon": 9.1801, "lines": ["M1"]},
        "beta": {"id": "beta", "name": "Beta", "lat": 45.4651, "lon": 9.1901, "lines": ["M1"]},
        "gamma": {"id": "gamma", "name": "Gamma", "lat": 45.4701, "lon": 9.2001, "lines": ["M1"]},
    },
    "lines": {"M1": {}},
}


def build_into(directory: Path) -> list[Path]:
    outputs = g.build(
        g.GtfsSource(SOURCE),
        dt.date(2026, 10, 5),
        7,
        metro_reference=REFERENCE,
        stop_names={"101": "P.le Cadorna fronte 1"},
        line_modes={"90": "FILOBUS"},
        built_at="fixture",
    )
    return g.write_outputs(outputs, directory)


def main() -> int:
    if "--check" in sys.argv:
        with tempfile.TemporaryDirectory() as tmp:
            for path in build_into(Path(tmp)):
                committed = OUT / path.name
                if not committed.exists() or committed.read_bytes() != path.read_bytes():
                    print(f"{committed.relative_to(REPO)} is out of date: run {Path(__file__).relative_to(REPO)}")
                    return 1
        print("GTFS fixture up to date")
        return 0
    for path in build_into(OUT):
        print(f"wrote {path.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
