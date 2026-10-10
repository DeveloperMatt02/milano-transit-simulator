# Mini GTFS fixture

A hand-written feed that reproduces the quirks of the Comune di Milano / AMAT feed, used by `tests/python/test_gtfs.py`.

| Case | Where |
| --- | --- |
| Metro stop ids are names, platforms of one station have different ids (`BETA`, `BETA M1`) | `stops.txt` |
| Lower-case stop names (prettified, or replaced by the `tpl_fermate` names) | `stops.txt` |
| Services defined mostly in `calendar_dates.txt`; one service in `calendar.txt` with a removed date | `calendar*.txt` |
| Different end of coverage per mode (`surface_end_date`, `mm_end_date` in `feed_info.txt`): the tram service stops on 2026-10-07 | `feed_info.txt`, `calendar_dates.txt` |
| Short-turn trip on the metro, reverse direction | `trips.txt` |
| Times past 24:00 (bus crossing midnight, night bus starting at 25:30), single-digit hours (`9:00:00`) | `stop_times.txt` |
| Rows of one trip out of `stop_sequence` order (`m1_b`), rows of one trip scattered through the file (`m1_c`), as in the real feed | `stop_times.txt` |
| Trip whose service is outside the export window (`m1_old`) | `trips.txt` |
| Shape with redundant collinear points (`S1`) | `shapes.txt` |

The export window used by the tests is 2026-10-05 (Monday) + 7 days.
