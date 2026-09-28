"""Build ``js/data/metro-network.js`` from OpenStreetMap station coordinates.

The line topology (station order, branches) is defined by hand below because
OSM route relations are split per direction/branch and are not always complete.
Coordinates come from ``data/raw/osm_raw_data.json`` (see download_open_data.py).

Branching lines are modelled as a *trunk* plus *branches* that share their
junction station with the trunk:

* M1: trunk Sesto 1° Maggio -> Pagano, branches to Rho Fieramilano and Bisceglie
* M2: branches Gessate / Cologno Nord -> Cascina Gobba, trunk Cascina Gobba ->
      Famagosta, branches to Assago Milanofiori Forum and Abbiategrasso
"""

from __future__ import annotations

import json
import sys

from common import JS_DATA_DIR, RAW_DIR, write_js_constant

LINES = {
    "M1": {
        "name": "Linea M1 (Rossa)",
        "color": "#F12D2D",
        "trunk": [
            "Sesto 1° Maggio FS", "Sesto Rondò", "Sesto Marelli", "Villa San Giovanni",
            "Precotto", "Gorla", "Turro", "Rovereto", "Pasteur", "Loreto", "Lima",
            "Porta Venezia", "Palestro", "San Babila", "Duomo", "Cordusio", "Cairoli",
            "Cadorna FN", "Conciliazione", "Pagano",
        ],
        "branch_rho": [
            "Pagano", "Buonarroti", "Amendola", "Lotto", "QT8", "Lampugnano",
            "Uruguay", "Bonola", "San Leonardo", "Molino Dorino", "Pero", "Rho Fieramilano",
        ],
        "branch_bisceglie": [
            "Pagano", "Wagner", "De Angeli", "Gambara", "Bande Nere", "Primaticcio",
            "Inganni", "Bisceglie",
        ],
    },
    "M2": {
        "name": "Linea M2 (Verde)",
        "color": "#15A03F",
        "branch_gessate": [
            "Gessate", "Cascina Antonietta", "Gorgonzola", "Villa Pompea", "Bussero",
            "Cassina de' Pecchi", "Villa Fiorita", "Cernusco sul Naviglio", "Cascina Burrona",
            "Vimodrone", "Cascina Gobba",
        ],
        "branch_cologno": ["Cologno Nord", "Cologno Centro", "Cologno Sud", "Cascina Gobba"],
        "trunk": [
            "Cascina Gobba", "Crescenzago", "Cimiano", "Udine", "Lambrate FS", "Piola", "Loreto",
            "Caiazzo", "Centrale FS", "Gioia", "Garibaldi FS", "Moscova", "Lanza", "Cadorna FN",
            "Sant'Ambrogio", "Sant'Agostino", "Porta Genova FS", "Romolo", "Famagosta",
        ],
        "branch_assago": ["Famagosta", "Assago Milanofiori Nord", "Assago Milanofiori Forum"],
        "branch_abbiategrasso": ["Famagosta", "Abbiategrasso-Chiesa Rossa"],
    },
    "M3": {
        "name": "Linea M3 (Gialla)",
        "color": "#F7D117",
        "trunk": [
            "Comasina", "Affori FN", "Affori Centro", "Dergano", "Maciachini", "Zara",
            "Sondrio", "Centrale FS", "Repubblica", "Turati", "Montenapoleone", "Duomo",
            "Missori", "Crocetta", "Porta Romana", "Lodi TIBB", "Brenta", "Corvetto",
            "Porto di Mare", "Rogoredo FS", "San Donato",
        ],
    },
    "M4": {
        "name": "Linea M4 (Blu)",
        "color": "#0F74C4",
        "trunk": [
            "San Cristoforo FS", "Segneri", "Gelsomini", "Frattini", "Tolstoj", "Bolivar",
            "California", "Coni Zugna", "Sant'Ambrogio", "De Amicis", "Vetra", "Santa Sofia",
            "Sforza-Policlinico", "San Babila", "Tricolore", "Dateo", "Susa", "Argonne",
            "Stazione Forlanini", "Repetti", "Linate Aeroporto",
        ],
    },
    "M5": {
        "name": "Linea M5 (Lilla)",
        "color": "#9C35A5",
        "trunk": [
            "Bignami", "Ponale", "Bicocca", "Ca' Granda", "Istria", "Marche", "Zara",
            "Isola", "Garibaldi FS", "Monumentale", "Cenisio", "Gerusalemme", "Domodossola FN",
            "Tre Torri", "Portello", "Lotto", "Segesta", "San Siro Ippodromo", "San Siro Stadio",
        ],
    },
}

# Used when a station cannot be matched in the OSM export.
MANUAL_COORDINATES = {
    "sesto_1_maggio": (45.5413, 9.2415),
    "cadorna": (45.4682, 9.1764),
    "centrale": (45.4846, 9.2028),
    "garibaldi": (45.4836, 9.1878),
    "lotto": (45.4795, 9.1432),
    "zara": (45.4926, 9.1928),
    "duomo": (45.4641, 9.1885),
    "loreto": (45.4851, 9.2173),
    "san_babila": (45.4665, 9.1983),
    "sant_ambrogio": (45.4623, 9.1724),
    "portello": (45.4802, 9.1506),
    "lambrate": (45.4844, 9.2356),
}

_REPLACEMENTS = [
    ("°", ""), ("º", ""), (" ", "_"), ("-", "_"), ("'", "_"), (".", ""),
    ("à", "a"), ("è", "e"), ("é", "e"), ("ì", "i"), ("ò", "o"), ("ù", "u"),
    ("_fs", ""), ("_fn", ""), ("fieramilano", "fiera"), ("chiesa_rossa", ""),
]


def station_key(name: str) -> str:
    """Stable identifier for a station, e.g. "Sesto 1° Maggio FS" -> "sesto_1_maggio"."""
    key = name.lower()
    for old, new in _REPLACEMENTS:
        key = key.replace(old, new)
    while "__" in key:
        key = key.replace("__", "_")
    return key.strip("_")


def display_name(name: str) -> str:
    return name.replace("-Chiesa Rossa", "").replace(" FS", "").replace(" FN", "")


def iter_paths(line: dict):
    for key, value in line.items():
        if key not in ("name", "color"):
            yield key, value


def build_network(osm_stations: list[dict]) -> dict:
    osm_by_key = {station_key(s["name"]): s for s in osm_stations}

    def coordinates(name: str) -> tuple[float, float]:
        key = station_key(name)
        if key in osm_by_key:
            return osm_by_key[key]["lat"], osm_by_key[key]["lon"]
        if key in MANUAL_COORDINATES:
            return MANUAL_COORDINATES[key]
        # Last resort: partial match (e.g. "Rho Fieramilano" vs "Rho Fiera Milano").
        for osm_key, station in osm_by_key.items():
            if key in osm_key or osm_key in key:
                print(f"  ! '{name}' matched by substring with OSM station '{station['name']}'")
                return station["lat"], station["lon"]
        raise KeyError(f"No coordinates found for station '{name}'. Add it to MANUAL_COORDINATES.")

    lines_by_station: dict[str, list[str]] = {}
    for line_id, line in LINES.items():
        for _, names in iter_paths(line):
            for name in names:
                served = lines_by_station.setdefault(station_key(name), [])
                if line_id not in served:
                    served.append(line_id)

    network = {"stations": {}, "lines": {}}
    for line_id, line in LINES.items():
        network["lines"][line_id] = {"id": line_id, "name": line["name"], "color": line["color"], "paths": {}}
        for path_key, names in iter_paths(line):
            ids = []
            for name in names:
                key = station_key(name)
                ids.append(key)
                if key not in network["stations"]:
                    lat, lon = coordinates(name)
                    served = lines_by_station[key]
                    network["stations"][key] = {
                        "id": key,
                        "name": display_name(name),
                        "lat": lat,
                        "lon": lon,
                        "lines": served,
                        "interchanges": [l for l in served if l != served[0]],
                    }
            network["lines"][line_id]["paths"][path_key] = ids
    return network


def main() -> int:
    raw_file = RAW_DIR / "osm_raw_data.json"
    if not raw_file.exists():
        print(f"Missing {raw_file}. Run: python scripts/download_open_data.py", file=sys.stderr)
        return 1
    osm_stations = json.loads(raw_file.read_text(encoding="utf-8")).get("stations", [])
    print(f"Loaded {len(osm_stations)} OSM station nodes")
    network = build_network(osm_stations)
    write_js_constant(
        JS_DATA_DIR / "metro-network.js",
        "METRO_NETWORK",
        network,
        "Milan metro network: stations (OpenStreetMap coordinates, ODbL) and line topology.",
    )
    print(f"Stations: {len(network['stations'])}, lines: {len(network['lines'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
