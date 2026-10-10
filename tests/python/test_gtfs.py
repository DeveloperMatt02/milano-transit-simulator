"""Tests for scripts/build_gtfs.py on the mini GTFS fixture (tests/python/fixtures/gtfs_mini).

Run with:  python -m unittest discover -s tests/python
Set GTFS_REAL=1 to also run the smoke test on data/raw/gtfs.zip (about a minute).
"""

import datetime as dt
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts"))

import build_gtfs as g  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "gtfs_mini"
START = dt.date(2026, 10, 5)  # Monday
DAYS = 7

REFERENCE = {
    "stations": {
        "alfa": {"id": "alfa", "name": "Alfa", "lat": 45.4601, "lon": 9.1801, "lines": ["M1"]},
        "beta": {"id": "beta", "name": "Beta", "lat": 45.4651, "lon": 9.1901, "lines": ["M1"]},
        "gamma": {"id": "gamma", "name": "Gamma", "lat": 45.4701, "lon": 9.2001, "lines": ["M1"]},
        # Delta FS is deliberately missing: it must become a new station.
    },
    "lines": {"M1": {}},
}
STOP_NAMES = {"101": "P.le Cadorna fronte 1"}
LINE_MODES = {"90": "FILOBUS"}


def build(source=FIXTURE, **kwargs):
    options = dict(metro_reference=REFERENCE, stop_names=STOP_NAMES, line_modes=LINE_MODES)
    options.update(kwargs)
    return g.build(g.GtfsSource(source), START, DAYS, **options)


class Helpers(unittest.TestCase):
    def test_parse_gtfs_time(self):
        self.assertEqual(g.parse_gtfs_time("05:30:00"), 19800)
        self.assertEqual(g.parse_gtfs_time("9:00:00"), 32400)
        self.assertEqual(g.parse_gtfs_time("25:30:15"), 91815)
        for bad in ("", "12:00", "aa:bb:cc", "10:61:00"):
            with self.assertRaises(ValueError):
                g.parse_gtfs_time(bad)

    def test_prettify_name(self):
        self.assertEqual(g.prettify_name("via dante (cordusio)"), "Via Dante (Cordusio)")
        self.assertEqual(g.prettify_name("duomo m1 m3"), "Duomo M1 M3")
        self.assertEqual(g.prettify_name("v.le gran sasso"), "V.le Gran Sasso")
        self.assertEqual(g.prettify_name("l.go augusto"), "L.go Augusto")
        self.assertEqual(g.prettify_name("DELTA FS"), "Delta FS")
        self.assertEqual(g.prettify_name("S.AGOSTINO"), "S.Agostino")
        self.assertEqual(g.prettify_name("cantu'/orefici - gratosoglio"), "Cantu'/Orefici - Gratosoglio")
        self.assertEqual(g.prettify_name("bicocca (universit\u00c3\u00a0)"), "Bicocca (Università)")

    def test_repair_text(self):
        self.assertEqual(g.repair_text("Via Gallarate Via Cefal\u00c3\u00b9"), "Via Gallarate Via Cefalù")
        self.assertEqual(g.repair_text("Città"), "Città")  # already correct text is left alone
        self.assertEqual(g.repair_text(""), "")

    def test_polyline_round_trip(self):
        points = [(45.46, 9.18), (45.465123, 9.190456), (45.4749, 9.2101)]
        decoded = g.decode_polyline(g.encode_polyline(points))
        for (a, b), (c, d) in zip(points, decoded):
            self.assertAlmostEqual(a, c, places=5)
            self.assertAlmostEqual(b, d, places=5)

    def test_simplify_keeps_shape_within_tolerance(self):
        a, b = (45.46, 9.18), (45.475, 9.21)
        line = [(a[0] + (b[0] - a[0]) * i / 10, a[1] + (b[1] - a[1]) * i / 10) for i in range(11)]
        line[5] = (line[5][0] + 0.00055, line[5][1])  # ~60 m bump
        out = g.simplify(line, tolerance_m=5)
        self.assertLess(len(out), len(line))
        self.assertEqual(out[0], line[0])
        self.assertEqual(out[-1], line[-1])
        self.assertIn(line[5], out)
        straight = g.simplify([a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), b], tolerance_m=5)
        self.assertEqual(straight, [a, b])

    def test_size_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.json"
            path.write_text(json.dumps(list(range(5000))))
            total = g.check_size_budget([path], budget_bytes=10**6)
            self.assertGreater(total, 0)
            with self.assertRaises(g.BudgetExceeded):
                g.check_size_budget([path], budget_bytes=100)


class Calendar(unittest.TestCase):
    def setUp(self):
        self.dates = g.service_dates(g.GtfsSource(FIXTURE))

    def test_calendar_and_calendar_dates(self):
        b_all = self.dates["b_all"]
        self.assertIn(dt.date(2026, 10, 5), b_all)
        self.assertNotIn(dt.date(2026, 10, 8), b_all)  # removed by calendar_dates (exception_type 2)
        self.assertEqual(len(b_all), 6)
        self.assertEqual(self.dates["m_sat"], {dt.date(2026, 10, 10)})

    def test_masks(self):
        masks = g.service_masks(self.dates, g.window_dates(START, DAYS))
        self.assertEqual(masks["m_wd"], 0b0011111)
        self.assertEqual(masks["m_sat"], 1 << 5)
        self.assertEqual(masks["m_sun"], 1 << 6)
        self.assertEqual(masks["t_wd"], 0b0000111)
        self.assertEqual(masks["b_all"], 0b1110111)
        self.assertNotIn("old", masks)  # no date inside the window


class MetroStations(unittest.TestCase):
    def test_line_constrained_nearest_match(self):
        stops = {
            "ALFA": (45.4600, 9.1800, "ALFA"),
            "BETA M1": (45.4650, 9.1900, "BETA M1"),
            "BETA": (45.4652, 9.1903, "BETA"),
            "OMEGA": (45.5200, 9.3000, "OMEGA"),
        }
        lines = {k: {"M1"} for k in stops}
        mapping, new, warnings = g.match_metro_stations(stops, lines, REFERENCE)
        self.assertEqual(mapping["ALFA"], "alfa")
        self.assertEqual(mapping["BETA"], "beta")
        self.assertEqual(mapping["BETA M1"], "beta")
        self.assertEqual(mapping["OMEGA"], "omega")
        self.assertIn("omega", new)
        self.assertTrue(any("OMEGA" in w for w in warnings))

    def test_other_line_is_not_matched(self):
        stops = {"ALFA": (45.4600, 9.1800, "ALFA")}
        mapping, new, _ = g.match_metro_stations(stops, {"ALFA": {"M2"}}, REFERENCE)
        # Same name as a reference station of another line: a new station with a line suffix.
        self.assertEqual(mapping["ALFA"], "alfa_m2")
        self.assertIn("alfa_m2", new)


class Build(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = build()
        cls.net = cls.out["network"]
        cls.tt = cls.out["timetable"]

    def route(self, name):
        return next(r for r in self.net["routes"] if r["name"] == name)

    def trips(self):
        t = self.tt["trips"]
        return list(zip(t["profile"], t["start"], t["service"]))

    def test_routes_modes_colors_and_coverage(self):
        m1, t15, b90, n25 = (self.route(n) for n in ("M1", "15", "90", "N25"))
        self.assertEqual((m1["mode"], t15["mode"], b90["mode"], n25["mode"]), ("METRO", "TRAM", "FILOBUS", "BUS"))
        self.assertEqual(m1["color"], "#FF0000")
        self.assertIsNone(t15["color"])
        self.assertEqual(m1["coverage_end"], "2026-10-11")
        self.assertEqual(t15["coverage_end"], "2026-10-07")  # tram feed expires earlier
        self.assertEqual(b90["coverage_end"], "2026-10-11")

    def test_window_filters_trips_and_dedups_profiles(self):
        self.assertEqual(len(self.trips()), 7)  # m1_old is outside the window
        self.assertEqual(len(self.tt["profiles"]), 6)  # m1_a and m1_b share a profile
        self.assertEqual(len(self.net["patterns"]), 6)
        starts = self.tt["trips"]["start"]
        self.assertEqual(starts, sorted(starts))
        self.assertEqual(self.tt["window"], {"start": "2026-10-05", "days": 7})

    def test_profile_offsets_and_out_of_order_rows(self):
        trips = self.trips()
        early = [t for t in trips if t[1] in (19800, 20400)]
        self.assertEqual(len(early), 2)
        self.assertEqual(early[0][0], early[1][0])  # same profile despite m1_b rows out of order
        profile = self.tt["profiles"][early[0][0]]
        self.assertEqual(profile["arrivals"], [0, 120, 240, 360])
        self.assertEqual(profile["dwells"], [0, 20, 20, 0])

    def test_scattered_rows_of_a_trip(self):
        short_turn = [t for t in self.trips() if t[1] == 36000]  # m1_c, last row elsewhere in the file
        self.assertEqual(len(short_turn), 1)
        profile = self.tt["profiles"][short_turn[0][0]]
        self.assertEqual(profile["arrivals"], [0, 120, 240])
        self.assertEqual(len(self.net["patterns"][profile["pattern"]]["stops"]), 3)

    def test_times_past_midnight(self):
        by_start = {t[1]: t for t in self.trips()}
        self.assertIn(85800, by_start)  # 23:50 bus crossing midnight
        b90 = self.tt["profiles"][by_start[85800][0]]
        self.assertEqual(b90["arrivals"], [0, 900, 1800])
        self.assertEqual(b90["dwells"], [0, 30, 0])
        self.assertIn(91800, by_start)  # night bus at 25:30
        n25 = self.tt["profiles"][by_start[91800][0]]
        self.assertNotIn("dwells", n25)  # omitted when all zero

    def test_service_masks_are_attached_to_trips(self):
        masks = self.tt["services"]
        by_start = {t[1]: t for t in self.trips()}
        self.assertEqual(masks[by_start[19800][2]], 0b0011111)  # weekday metro
        self.assertEqual(masks[by_start[85800][2]], 0b1110111)  # bus every day but Thursday

    def test_stops_names_and_metro_stations(self):
        stops = self.net["stops"]
        ids = [s["id"] for s in stops]
        self.assertNotIn("999", ids)  # unused stops are not exported
        self.assertEqual(len(stops), 10)
        by_id = {s["id"]: s for s in stops}
        self.assertEqual(by_id["101"]["name"], "P.le Cadorna fronte 1")  # tpl_fermate name wins
        self.assertEqual(by_id["104"]["name"], "V.le Gran Sasso")
        self.assertEqual(by_id["BETA"]["station"], "beta")
        self.assertEqual(by_id["BETA M1"]["station"], "beta")
        self.assertIsNone(by_id["101"]["station"])
        stations = {s["id"]: s for s in self.net["stations"]}
        self.assertEqual(set(stations), {"alfa", "beta", "gamma", "delta_fs"})
        self.assertEqual(stations["beta"]["name"], "Beta")
        self.assertEqual(stations["delta_fs"]["name"], "Delta FS")
        self.assertEqual(stations["alfa"]["lines"], ["M1"])
        self.assertEqual(sorted(stops[i]["id"] for i in stations["beta"]["stops"]), ["BETA", "BETA M1"])

    def test_patterns_reference_valid_stops_and_shapes(self):
        shapes = self.out["shapes"]["shapes"]
        for p in self.net["patterns"]:
            self.assertTrue(all(0 <= i < len(self.net["stops"]) for i in p["stops"]))
            self.assertTrue(p["shape"] is None or 0 <= p["shape"] < len(shapes))
        self.assertEqual(len(shapes), 3)  # S1, S2, S3
        headsigns = {p["headsign"] for p in self.net["patterns"]}
        self.assertIn("Delta FS", headsigns)

    def test_meta(self):
        meta = self.out["meta"]
        self.assertEqual(meta["feed"]["version"], "999")
        self.assertEqual(meta["feed"]["end_dates"], {"surface": "2026-10-07", "metro": "2026-10-11"})
        self.assertEqual(meta["counts"]["trips"], 7)
        self.assertIn("CC BY", meta["attribution"])

    def test_deterministic_and_zip_equals_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / "gtfs.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                for f in FIXTURE.glob("*.txt"):
                    zf.write(f, f.name)
            again = build(archive)
        for key in ("network", "timetable", "shapes"):
            self.assertEqual(g.dumps(self.out[key]), g.dumps(again[key]), key)

    def test_write_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = g.write_outputs(self.out, Path(tmp))
            self.assertEqual(sorted(p.name for p in paths), ["meta.json", "network.json", "shapes.json", "timetable.json"])
            for p in paths:
                json.loads(p.read_text(encoding="utf-8"))


class EdgeCases(unittest.TestCase):
    """Feed quirks allowed by the GTFS spec but absent from the main fixture."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        feed = cls.tmp / "feed"
        shutil.copytree(FIXTURE, feed)
        with open(feed / "trips.txt", "a", encoding="utf-8") as f:
            f.write("B90,b_all,b90_interp,circolare,,,,S3,,,\n")
            f.write("B90,b_all,b90_dup,circolare,,,,S3,,,\n")
            f.write("B90,b_all,b90_back,circolare,,,,S3,,,\n")
            f.write("B90,b_all,b90_untimed,circolare,,,,S3,,,\n")
            f.write("X1,b_all,ghost,nowhere,,,,,,,\n")
        with open(feed / "stop_times.txt", "a", encoding="utf-8") as f:
            f.write("b90_interp,08:00:00,08:00:00,103,1,,,,\n")
            f.write("b90_interp,,,104,2,,,,\n")  # non-timepoint stop
            f.write("b90_interp,08:10:00,08:10:00,101,3,,,,\n")
            f.write("b90_dup,09:00:00,09:00:00,103,1,,,,\n")
            f.write("b90_dup,09:00:00,09:00:00,105,1,,,,\n")  # repeated stop_sequence
            f.write("b90_dup,09:05:00,09:05:00,101,2,,,,\n")
            f.write("b90_back,10:00:00,10:00:00,103,1,,,,\n")
            f.write("b90_back,09:59:00,09:59:00,104,2,,,,\n")  # goes back in time
            f.write("b90_back,10:10:00,10:10:00,101,3,,,,\n")
            f.write("b90_untimed,,,103,1,,,,\n")
            f.write("b90_untimed,11:00:00,11:00:00,101,2,,,,\n")
            f.write("ghost,12:00:00,12:00:00,101,1,,,,\n")
        cls.out = build(feed)
        cls.warnings = " | ".join(cls.out["meta"]["warnings"])

    def profiles(self, start, route_name="90"):
        """Profiles of the trips of a route starting at `start` (several trips can share a start)."""
        net, timetable = self.out["network"], self.out["timetable"]
        out = []
        for s, p in zip(timetable["trips"]["start"], timetable["trips"]["profile"]):
            profile = timetable["profiles"][p]
            if s == start and net["routes"][net["patterns"][profile["pattern"]]["route"]]["name"] == route_name:
                out.append(profile)
        return out

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_interpolates_stops_without_times(self):
        self.assertEqual([p["arrivals"] for p in self.profiles(28800)], [[0, 300, 600]])
        self.assertIn("interpolated", self.warnings)

    def test_drops_repeated_stop_sequence(self):
        self.assertEqual([p["arrivals"] for p in self.profiles(32400)], [[0, 300]])
        self.assertIn("repeated a stop_sequence", self.warnings)

    def test_clamps_times_going_backwards(self):
        self.assertEqual([p["arrivals"] for p in self.profiles(36000)], [[0, 0, 600]])
        self.assertIn("not monotonic", self.warnings)

    def test_skips_untimed_and_orphan_trips(self):
        self.assertEqual(self.profiles(39600), [])
        self.assertEqual(self.profiles(43200, "X1"), [])
        self.assertIn("no time at the first or last stop", self.warnings)
        self.assertIn("missing from routes.txt", self.warnings)

    def test_empty_window(self):
        out = g.build(g.GtfsSource(FIXTURE), dt.date(2027, 1, 1), 7, metro_reference=REFERENCE)
        self.assertEqual(out["timetable"]["trips"]["start"], [])
        self.assertEqual(out["meta"]["counts"]["trips"], 0)


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_writes_window_with_previous_service_day(self):
        code = g.main(["--gtfs", str(FIXTURE), "--out", str(self.tmp), "--start", "2026-10-06", "--days", "6"])
        self.assertEqual(code, 0)
        timetable = json.loads((self.tmp / "timetable.json").read_text(encoding="utf-8"))
        self.assertEqual(timetable["window"], {"start": "2026-10-05", "days": 7})

    def test_over_budget_keeps_previous_output(self):
        (self.tmp / "network.json").write_text("previous", encoding="utf-8")
        code = g.main(["--gtfs", str(FIXTURE), "--out", str(self.tmp), "--start", "2026-10-06", "--budget-mb", "0.000001"])
        self.assertEqual(code, 2)
        self.assertEqual((self.tmp / "network.json").read_text(encoding="utf-8"), "previous")
        self.assertFalse((self.tmp / "timetable.json").exists())

    def test_rejects_empty_window(self):
        with self.assertRaises(SystemExit):
            g.main(["--gtfs", str(FIXTURE), "--out", str(self.tmp), "--days", "0"])

    def test_missing_feed(self):
        self.assertEqual(g.main(["--gtfs", str(self.tmp / "nope.zip"), "--out", str(self.tmp)]), 1)


class Download(unittest.TestCase):
    """fetch_gtfs keeps the previous gtfs.zip when the new download is not a valid feed."""

    def setUp(self):
        import download_open_data as dl

        self.dl = dl
        self.tmp = Path(tempfile.mkdtemp())
        self.saved = (dl.RAW_DIR, dl.download)
        dl.RAW_DIR = self.tmp
        (self.tmp / "gtfs.zip").write_bytes(b"previous")

    def tearDown(self):
        self.dl.RAW_DIR, self.dl.download = self.saved
        shutil.rmtree(self.tmp)

    def fake_download(self, payload):
        def download(url, destination, overwrite=False):
            Path(destination).write_bytes(payload)
            return destination

        self.dl.download = download

    def test_invalid_download_keeps_previous_file(self):
        self.fake_download(b"<html>maintenance</html>")
        with self.assertRaises(RuntimeError):
            self.dl.fetch_gtfs(force=True)
        self.assertEqual((self.tmp / "gtfs.zip").read_bytes(), b"previous")
        self.assertFalse((self.tmp / "gtfs.zip.part").exists())

    def test_valid_download_replaces_file(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as zf:
            for f in FIXTURE.glob("*.txt"):
                zf.write(f, f.name)
        self.fake_download(buffer.getvalue())
        self.dl.fetch_gtfs(force=True)
        self.assertTrue(zipfile.is_zipfile(self.tmp / "gtfs.zip"))


@unittest.skipUnless(os.environ.get("GTFS_REAL") == "1" and (REPO / "data/raw/gtfs.zip").exists(), "set GTFS_REAL=1 with data/raw/gtfs.zip")
class RealFeed(unittest.TestCase):
    def test_real_feed_smoke(self):
        reference = g.load_metro_reference(REPO / "js/data/metro-network.js")
        source = g.GtfsSource(REPO / "data/raw/gtfs.zip")
        meta_start = g.feed_start(source)
        out = g.build(source, meta_start, 14, metro_reference=reference)
        stations = {s["id"] for s in out["network"]["stations"]}
        self.assertTrue(set(reference["stations"]) <= stations, set(reference["stations"]) - stations)
        self.assertEqual({r["name"] for r in out["network"]["routes"] if r["mode"] == "METRO"}, {"M1", "M2", "M3", "M4", "M5"})
        with tempfile.TemporaryDirectory() as tmp:
            paths = g.write_outputs(out, Path(tmp))
            self.assertLessEqual(g.check_size_budget(paths, 5 * 1024 * 1024), 5 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
