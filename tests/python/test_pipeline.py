"""Unit tests for the pure helpers of the data pipeline (standard library only).

Run with:  python -m unittest discover -s tests/python
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import build_metro_frequencies as freq  # noqa: E402
import build_metro_network as metro  # noqa: E402
import build_surface_network as surface  # noqa: E402
from common import hhmm_to_minutes, minutes_to_hhmm, to_service_minutes  # noqa: E402


class TimeHelpers(unittest.TestCase):
    def test_parse_and_format(self):
        self.assertEqual(hhmm_to_minutes("05:40"), 340)
        self.assertIsNone(hhmm_to_minutes("x"))
        self.assertEqual(minutes_to_hhmm(24 * 60 + 53), "24:53")

    def test_service_day(self):
        self.assertEqual(to_service_minutes(13), 24 * 60 + 13)  # 00:13 -> 24:13
        self.assertEqual(to_service_minutes(5 * 60), 5 * 60)


class MetroNetwork(unittest.TestCase):
    def test_station_keys(self):
        self.assertEqual(metro.station_key("Sesto 1° Maggio FS"), "sesto_1_maggio")
        self.assertEqual(metro.station_key("Sesto 1º Maggio FS"), "sesto_1_maggio")
        self.assertEqual(metro.station_key("Abbiategrasso-Chiesa Rossa"), "abbiategrasso")
        self.assertEqual(metro.station_key("Cassina de' Pecchi"), "cassina_de_pecchi")

    def test_topology(self):
        self.assertIn("Lambrate FS", metro.LINES["M2"]["trunk"])
        self.assertNotIn("Portello", metro.LINES["M1"]["branch_rho"])

    def test_build_network(self):
        names = {n for line in metro.LINES.values() for k, v in line.items() if k not in ("name", "color") for n in v}
        fake_osm = [{"name": n, "lat": 45.46 + i * 1e-4, "lon": 9.19} for i, n in enumerate(sorted(names))]
        network = metro.build_network(fake_osm)
        self.assertEqual(len(network["stations"]), len({metro.station_key(n) for n in names}))
        self.assertEqual(network["stations"]["loreto"]["lines"], ["M1", "M2"])
        self.assertEqual(network["stations"]["loreto"]["interchanges"], ["M2"])
        self.assertEqual(network["stations"]["lambrate"]["name"], "Lambrate")
        trunk = network["lines"]["M2"]["paths"]["trunk"]
        self.assertEqual(trunk[trunk.index("lambrate") - 1 : trunk.index("lambrate") + 2], ["udine", "lambrate", "piola"])

    def test_missing_coordinates_raise(self):
        with self.assertRaises(KeyError):
            metro.build_network([])


class MetroFrequencies(unittest.TestCase):
    ROWS = [
        # Two directions of M3 on weekdays, plus an after-midnight run.
        {"linea": "3", "tipo_giorno": "L", "corse_gior": "236", "corse_punt": "36", "corse_morb": "24", "corse_sera": "13", "inizio": "05:40", "fine": "00:53"},
        {"linea": "3", "tipo_giorno": "L", "corse_gior": "236", "corse_punt": "35", "corse_morb": "24", "corse_sera": "13", "inizio": "05:45", "fine": "00:50"},
        {"linea": "9", "tipo_giorno": "L", "corse_gior": "1", "corse_punt": "0", "corse_morb": "0", "corse_sera": "0", "inizio": "05:00", "fine": "06:00"},
    ]

    def test_aggregation(self):
        result = freq.aggregate(self.ROWS)
        m3 = result["M3"]["L"]
        self.assertEqual(m3["peak_headway"], round(7200 / 35.5))
        self.assertEqual(m3["mid_headway"], 300)
        self.assertEqual(m3["first_departure"], "05:40")
        # "00:53" must be treated as after midnight, not as the earliest time of the day.
        self.assertEqual(m3["last_arrival"], "24:53")

    def test_missing_lines_fall_back(self):
        result = freq.aggregate(self.ROWS)
        self.assertEqual(result["M1"]["S"]["peak_headway"], freq.FALLBACK["peak_headway"])


class SurfaceNetwork(unittest.TestCase):
    def test_regular_route(self):
        self.assertEqual(surface.service_window("05:32", "01:55", 100), (5 * 60 + 32, 25 * 60 + 55))

    def test_24h_route(self):
        self.assertEqual(surface.service_window("01:30", "01:55", 172), (3 * 60, 27 * 60))

    def test_night_route(self):
        start, end = surface.service_window("00:30", "05:30", 10)
        self.assertEqual((start, end), (24 * 60 + 30, 29 * 60 + 30))

    def test_headway_clamping(self):
        self.assertEqual(surface.headway(0, 600, 180, 1200), 600)
        self.assertEqual(surface.headway(100, 600, 180, 1200), 180)
        self.assertEqual(surface.headway(12, 600, 180, 1200), 600)


if __name__ == "__main__":
    unittest.main()
