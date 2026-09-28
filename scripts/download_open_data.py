"""Download the raw public-transport datasets used by the simulator.

Sources
-------
* Comune di Milano Open Data portal (https://dati.comune.milano.it), CC BY 4.0:
  - ``tpl_metroorari.csv``  metro service summary (trips per time band, first/last run)
  - ``tpl_orari.csv``       surface lines service summary
  - ``tpl_fermate.csv``     surface stops with WGS84 coordinates
  - ``tpl_sequenza.csv``    ordered stop sequence of every surface route
* OpenStreetMap via the Overpass API (ODbL): metro station coordinates.

Files are stored in ``data/raw/`` (git-ignored). Use ``--force`` to re-download.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request

from common import RAW_DIR, USER_AGENT, download

OPEN_DATA_URLS = {
    "tpl_metroorari.csv": "https://dati.comune.milano.it/dataset/581f1e5c-cb68-4e12-8d43-4f24828f9a4f/resource/2f8141e5-122e-4b3c-a4b1-562d881f3f6f/download/tpl_metroorari.csv",
    "tpl_orari.csv": "https://dati.comune.milano.it/dataset/32112fb0-4c62-4ec0-aef4-e70b05f0fe41/resource/67bbf039-a22b-4ee3-b32e-31735bf1354d/download/tpl_orari.csv",
    "tpl_fermate.csv": "https://dati.comune.milano.it/dataset/ac494f5d-acd3-4fd3-8cfc-ed24f5c3d923/resource/2a52d51d-66fe-480b-a101-983aa2f6cbc3/download/tpl_fermate.csv",
    "tpl_sequenza.csv": "https://dati.comune.milano.it/dataset/a42d1ec5-1a9e-43e7-925e-32d7fc976bdd/resource/d4530625-dd71-4e8c-8eb4-bf4e26f2500e/download/tpl_sequenza.csv",
}

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
# Every metro station inside a bounding box that covers all suburban branches
# (Rho Fiera to the west, Gessate to the east, Assago to the south).
OVERPASS_QUERY = """
[out:json][timeout:60];
node["railway"="station"]["station"="subway"](45.35,9.00,45.65,9.46);
out body;
"""


def fetch_osm_stations(force: bool) -> None:
    destination = RAW_DIR / "osm_raw_data.json"
    if destination.exists() and not force:
        print(f"  = data/raw/{destination.name} already present, skipping")
        return
    print(f"  ↓ {OVERPASS_URL}")
    body = urllib.parse.urlencode({"data": OVERPASS_QUERY}).encode("utf-8")
    request = urllib.request.Request(OVERPASS_URL, data=body, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.loads(response.read().decode("utf-8"))

    stations = [
        {
            "id": str(element["id"]),
            "name": element["tags"]["name"],
            "lat": element["lat"],
            "lon": element["lon"],
            "tags": element["tags"],
        }
        for element in result.get("elements", [])
        if element.get("type") == "node" and element.get("tags", {}).get("name")
    ]
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({"stations": stations}, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"  ✓ saved data/raw/{destination.name} ({len(stations)} stations)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download files that already exist")
    args = parser.parse_args()

    print("Downloading Comune di Milano open data…")
    failures = 0
    for filename, url in OPEN_DATA_URLS.items():
        try:
            download(url, RAW_DIR / filename, overwrite=args.force)
        except Exception as error:  # noqa: BLE001 - report and continue with the other files
            failures += 1
            print(f"  ✗ {filename}: {error}", file=sys.stderr)

    print("Downloading metro station coordinates from OpenStreetMap…")
    try:
        fetch_osm_stations(args.force)
    except Exception as error:  # noqa: BLE001
        failures += 1
        print(f"  ✗ Overpass API: {error}", file=sys.stderr)

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
