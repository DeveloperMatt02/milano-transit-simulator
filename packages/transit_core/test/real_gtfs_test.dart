// Smoke test on the real GTFS datasets built by scripts/build_gtfs.py from the city's feed.
//
//   python3 scripts/build_gtfs.py --out ../../data/gtfs
//   GTFS_DIR=../../data/gtfs dart test test/real_gtfs_test.dart
//
// Skipped when GTFS_DIR is not set (the datasets are not committed). The "Dart core"
// workflow downloads the feed, builds the datasets and runs it on every push.
import 'dart:io';

import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

final _dir = Platform.environment['GTFS_DIR'];

void main() {
  group('real GTFS dataset', () {
    late GtfsDataset dataset;
    late ScheduleComposer composer;
    late PlaceRegistry places;
    late CivilDate buildDay;

    setUpAll(() {
      dataset = loadGtfsDir(_dir!);
      composer = ScheduleComposer(synthetic: newScheduler(), gtfs: dataset);
      places = composer.places();
      // The window starts the day before the build (night trips after midnight).
      buildDay = dataset.windowStart.addDays(1);
    });

    test('format, window and metro routes', () {
      expect(dataset.windowDays, 15);
      expect(dataset.tripCount, greaterThan(1000));
      for (final line in ['M1', 'M2', 'M3', 'M4', 'M5']) {
        expect(dataset.route(line)?.mode, TransitMode.metro, reason: line);
      }
      final metroStations = dataset.stations.map((s) => s.id).toSet();
      expect(metroStations, containsAll(metroNetwork.stations.keys));
    });

    test('every day of the window composes, with places for every stop', () {
      for (var d = buildDay; d <= dataset.windowEnd; d = d.addDays(1)) {
        final day = composer.compose(d);
        expect(day.trips, isNotEmpty, reason: '$d');
        for (final trip in day.trips) {
          for (var i = 0; i < trip.length; i++) {
            expect(trip.departures[i], greaterThanOrEqualTo(trip.arrivals[i]), reason: '${trip.id} @ $i');
            if (i > 0) {
              expect(trip.arrivals[i], greaterThanOrEqualTo(trip.departures[i - 1]), reason: '${trip.id} @ $i');
            }
          }
        }
        final unknown = {
          for (final trip in day.trips)
            for (final id in trip.stopIds)
              if (places[id] == null) id,
        };
        expect(unknown, isEmpty, reason: '$d: stops without coordinates');
      }
    });

    test('metro from GTFS on the build day, with vehicles and departure boards', () {
      final day = composer.compose(buildDay);
      final engine = TransitEngine(day.trips, places);
      for (final line in ['M1', 'M2', 'M3', 'M4', 'M5']) {
        if (day.sources[line] != TimetableSource.gtfs) continue;
        expect(day.trips.where((t) => t.lineId == line).length, greaterThan(100), reason: line);
      }
      final atPeak = engine.activeVehicles(8.25 * 3600);
      expect(atPeak.length, greaterThan(100));
      expect(engine.departures('duomo', 8.25 * 3600), isNotEmpty);
      // Same answer as checking every trip.
      for (var t = serviceDayStart; t < serviceDayEnd; t += 1800) {
        final expected = [
          for (final trip in engine.trips)
            if (isActiveAt(trip.startTime, trip.endTime, t)) trip.id,
        ];
        expect(engine.activeVehicles(t).map((v) => v.tripId).toList(), expected, reason: 't=$t');
      }
    });

    test('estimated lines are exactly the ones past their coverage', () {
      final day = composer.compose(buildDay);
      for (final line in day.estimatedLines) {
        expect(dataset.covers(line, buildDay), isFalse, reason: line);
      }
    });
  }, skip: _dir == null ? 'set GTFS_DIR to a data/gtfs directory to run' : false);
}
