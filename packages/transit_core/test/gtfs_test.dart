// GtfsDataset on the fixture built from tests/python/fixtures/gtfs_mini.
//
// Window 2026-10-05 (Monday) + 7 days. Trips (index: start, route, days):
//   0: 05:30 M1 → Delta FS, Mon–Fri      1: 05:40 M1 → Delta FS, Mon–Fri
//   2: 07:00 15 → Rozzano, Mon–Wed       3: 09:00 M1 → Alfa, Sun
//   4: 10:00 M1 → Gamma, Sat             5: 23:50 90, every day but Thu
//   6: 25:30 N25, every day but Thu
// Coverage ends: M1, 90, N25 2026-10-11; 15 2026-10-07.
import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

const _all = {'M1', '15', '90', 'N25'};

/// Moves trip 6 (N25) to 01:30 of its date: the "next calendar day" night convention.
void _nightBeforeThree(Map<String, dynamic> timetable) {
  final trips = timetable['trips'] as Map<String, dynamic>;
  (trips['start'] as List<dynamic>)[6] = 5400;
}

void main() {
  final dataset = fixtureDataset();
  final monday = CivilDate(2026, 10, 5);

  group('parsing', () {
    test('sizes and window', () {
      expect(dataset.stops, hasLength(10));
      expect(dataset.stations, hasLength(4));
      expect(dataset.routes, hasLength(4));
      expect(dataset.patterns, hasLength(6));
      expect(dataset.profiles, hasLength(6));
      expect(dataset.tripCount, 7);
      expect(dataset.shapes, hasLength(3));
      expect(dataset.windowStart, monday);
      expect(dataset.windowEnd, CivilDate(2026, 10, 11));
      expect(dataset.meta['built_at'], 'fixture');
    });

    test('routes, modes and coverage', () {
      expect(dataset.route('M1')!.mode, TransitMode.metro);
      expect(dataset.route('M1')!.color, '#FF0000');
      expect(dataset.route('15')!.mode, TransitMode.tram);
      expect(dataset.route('15')!.coverageEnd, CivilDate(2026, 10, 7));
      expect(dataset.route('90')!.mode, TransitMode.trolleybus);
      expect(dataset.route('N25')!.mode, TransitMode.bus);
      expect(dataset.route('nope'), isNull);
    });

    test('metro platforms map to their station', () {
      final beta = dataset.stops.firstWhere((s) => s.id == 'BETA M1');
      expect(beta.placeId, 'beta');
      final surface = dataset.stops.firstWhere((s) => s.id == '101');
      expect(surface.placeId, '101');
      expect(surface.wheelchair, 1);
      expect(dataset.stations.firstWhere((s) => s.id == 'beta').stops, [6, 7]);
    });

    test('places: stations plus surface stops, no platforms', () {
      final ids = dataset.places.map((p) => p.id).toList();
      expect(ids, ['alfa', 'beta', 'delta_fs', 'gamma', '101', '102', '103', '104', '105']);
    });

    test('unsupported format versions are rejected', () {
      Map<String, dynamic> withVersion(String file, Object? version) =>
          readJson('test/fixtures/gtfs_mini/$file')..['version'] = version;
      expect(
        () => GtfsDataset.fromJson(
          network: withVersion('network.json', 2),
          timetable: readJson('test/fixtures/gtfs_mini/timetable.json'),
        ),
        throwsFormatException,
      );
      expect(
        () => GtfsDataset.fromJson(
          network: readJson('test/fixtures/gtfs_mini/network.json'),
          timetable: withVersion('timetable.json', null),
        ),
        throwsFormatException,
      );
    });

    test('shapes and meta are optional', () {
      final bare = GtfsDataset.fromJson(
        network: readJson('test/fixtures/gtfs_mini/network.json'),
        timetable: readJson('test/fixtures/gtfs_mini/timetable.json'),
      );
      expect(bare.shapes, isEmpty);
      expect(bare.meta, isEmpty);
      expect(bare.tripCount, 7);
    });
  });

  group('window and coverage (ADR 0004)', () {
    test('dayIndex', () {
      expect(dataset.dayIndex(CivilDate(2026, 10, 4)), isNull);
      expect(dataset.dayIndex(monday), 0);
      expect(dataset.dayIndex(CivilDate(2026, 10, 11)), 6);
      expect(dataset.dayIndex(CivilDate(2026, 10, 12)), isNull);
    });

    test('covers needs route, window and coverage end', () {
      expect(dataset.covers('15', CivilDate(2026, 10, 7)), isTrue);
      expect(dataset.covers('15', CivilDate(2026, 10, 8)), isFalse);
      expect(dataset.covers('M1', CivilDate(2026, 10, 11)), isTrue);
      expect(dataset.covers('M1', CivilDate(2026, 10, 12)), isFalse);
      expect(dataset.covers('M1', CivilDate(2026, 10, 4)), isFalse);
      expect(dataset.covers('nope', monday), isFalse);
    });
  });

  group('tripsOnServiceDate', () {
    test('Monday: the weekday trips, sorted, with stations as stops', () {
      final trips = dataset.tripsOnServiceDate(monday, routes: _all);
      expect(trips.map((t) => t.id), ['M1-g0', 'M1-g1', '15-g2', '90-g5', 'N25-g6']);

      final m1 = trips.first;
      expect(m1.mode, TransitMode.metro);
      expect(m1.from, 'Alfa');
      expect(m1.to, 'Delta FS');
      expect(m1.stopIds, ['alfa', 'beta', 'gamma', 'delta_fs']);
      expect(m1.arrivals, [19800, 19920, 20040, 20160]);
      expect(m1.departures, [19800, 19940, 20060, 20160]);

      final tram = trips[2];
      expect(tram.from, 'P.le Cadorna fronte 1');
      expect(tram.to, 'Rozzano');
      expect(tram.arrivals, [25200, 25500, 25800]);
      expect(tram.departures, tram.arrivals);

      final trolley = trips[3];
      expect(trolley.arrivals, [85800, 86700, 87600]);
      expect(trolley.departures, [85800, 86730, 87600]);

      // Night trip written with times past 24:00: stays on its own date.
      expect(trips[4].arrivals, [91800, 92700]);
    });

    test('day masks: Thursday, Saturday, Sunday', () {
      List<String> ids(CivilDate d) => dataset.tripsOnServiceDate(d, routes: _all).map((t) => t.id).toList();
      expect(ids(CivilDate(2026, 10, 8)), ['M1-g0', 'M1-g1']);
      expect(ids(CivilDate(2026, 10, 10)), ['M1-g4', '90-g5', 'N25-g6']);
      expect(ids(CivilDate(2026, 10, 11)), ['M1-g3', '90-g5', 'N25-g6']);
    });

    test('route filter and dates outside the window', () {
      expect(dataset.tripsOnServiceDate(monday, routes: {'M1'}).map((t) => t.lineId).toSet(), {'M1'});
      expect(dataset.tripsOnServiceDate(CivilDate(2026, 10, 12), routes: _all), isEmpty);
    });

    group('night trips dated the next day (before 03:00)', () {
      final night = fixtureDataset(editTimetable: _nightBeforeThree);

      test('belong to the previous service day, shifted by 24 h', () {
        final trips = night.tripsOnServiceDate(monday, routes: _all);
        final n25 = trips.where((t) => t.lineId == 'N25').toList();
        // Monday's own 01:30 trip belongs to Sunday's service day; Tuesday's is shown here.
        expect(n25.map((t) => t.id), ['N25-g6+1']);
        expect(n25.single.arrivals, [91800, 92700]);
        expect(trips.last.id, 'N25-g6+1');
      });

      test('the day before the window still gets them', () {
        final trips = night.tripsOnServiceDate(CivilDate(2026, 10, 4), routes: _all);
        expect(trips.map((t) => t.id), ['N25-g6+1']);
      });

      test('not when the next day has no service or is outside the window', () {
        bool hasN25(CivilDate d) => night.tripsOnServiceDate(d, routes: _all).any((t) => t.lineId == 'N25');
        expect(hasN25(CivilDate(2026, 10, 7)), isFalse); // Thursday has no N25
        expect(hasN25(CivilDate(2026, 10, 11)), isFalse); // 10-12 is outside the window
      });

      test('nextDayRoutes restricts them', () {
        final trips = night.tripsOnServiceDate(monday, routes: _all, nextDayRoutes: const {});
        expect(trips.any((t) => t.id.endsWith('+1')), isFalse);
      });
    });
  });

  group('polylines', () {
    test('reference example of the encoding', () {
      expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), [
        (38.5, -120.2),
        (40.7, -120.95),
        (43.252, -126.453),
      ]);
    });

    test('fixture shapes decode like scripts/build_gtfs.py', () {
      expect(dataset.shape(1), [(45.475, 9.21), (45.46, 9.18)]);
      expect(dataset.shape(2), [(45.468, 9.176), (45.466, 9.185), (45.464, 9.19)]);
      expect(dataset.shape(0), hasLength(5));
      expect(decodePolyline(''), isEmpty);
    });
  });
}
