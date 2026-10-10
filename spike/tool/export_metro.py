"""Writes spike/map_spike_common/assets/metro_lines.json from js/data/metro-network.js.

The spike only needs the metro geometry (straight segments between stations) and the
line colours; it does not depend on the GTFS datasets, which are not committed.

    python3 spike/tool/export_metro.py
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))

from common import read_js_constant  # noqa: E402

# Noorda light colours, as in js/themes.js.
COLORS = {"M1": "#E2231A", "M2": "#00873F", "M3": "#F5C400", "M4": "#1165B0", "M5": "#8E4799"}


def main() -> int:
    network = read_js_constant(REPO / "js" / "data" / "metro-network.js")
    stations = network["stations"]
    lines = []
    for line_id in sorted(network["lines"]):
        paths = [
            [[round(stations[s]["lon"], 6), round(stations[s]["lat"], 6)] for s in path]
            for path in network["lines"][line_id]["paths"].values()
        ]
        lines.append({"id": line_id, "color": COLORS.get(line_id, "#888888"), "paths": paths})
    out = REPO / "spike" / "map_spike_common" / "assets" / "metro_lines.json"
    out.write_text(json.dumps({"lines": lines}, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {out.relative_to(REPO)}: {len(lines)} lines, {sum(len(l['paths']) for l in lines)} paths")
    return 0


if __name__ == "__main__":
    sys.exit(main())
