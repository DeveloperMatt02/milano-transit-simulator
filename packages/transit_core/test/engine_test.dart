// Unit tests of TransitEngine: positions, indexes and departure boards.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

Trip _trip(String id, List<String> stops, List<int> arrivals, List<int> departures,
        {String lineId = 'X1', String to = 'C'}) =>
    Trip(
      id: id,
      lineId: lineId,
      mode: TransitMode.bus,
      from: 'A',
      to: to,
      stopIds: stops,
      arrivals: Int32List.fromList(arrivals),
      departures: Int32List.fromList(departures),
    );

PlaceRegistry _places() => PlaceRegistry()
  ..addAll(const [
    Place(id: 'a', name: 'A', lat: 45.46, lon: 9.18),
    Place(id: 'b', name: 'B', lat: 45.47, lon: 9.18),
    Place(id: 'c', name: 'C', lat: 45.47, lon: 9.20),
  ]);

/// What js/simulation-engine.js does: every trip of the day is checked.
List<String> _bruteForce(List<Trip> trips, num t) => [
      for (final trip in sortTripsByStart(trips))
        if (isActiveAt(trip.startTime, trip.endTime, t)) trip.id,
    ];

void main() {
  group('vehicleState', () {
    final trip = _trip('t1', ['a', 'b', 'c'], [36000, 36300, 36600], [36000, 36330, 36600]);
    final engine = TransitEngine([trip], _places());

    test('null before the start and after the terminus', () {
      expect(engine.vehicleState(trip, 35999), isNull);
      expect(engine.vehicleState(trip, 36601), isNull);
    });

    test('stopped at the first stop at the start time', () {
      final s = engine.vehicleState(trip, 36000)!;
      expect(s.status, VehicleStatus.stopped);
      expect(s.stopIndex, 0);
      expect(s.currentStopId, 'a');
      expect(s.nextStopId, 'b');
      expect(s.secondsToNext, 300);
      expect(s.speed, 0);
      expect(s.angle, 0); // a -> b is due north
      expect(s.progress, 0.0);
    });

    test('moving halfway through a segment', () {
      final s = engine.vehicleState(trip, 36150)!;
      expect(s.status, VehicleStatus.moving);
      expect(s.stopIndex, 0);
      expect(s.lat, closeTo(45.465, 1e-9));
      expect(s.lon, closeTo(9.18, 1e-9));
      expect(s.segmentProgress, closeTo(0.5, 1e-12));
      expect(s.progress, closeTo(0.25, 1e-12));
      expect(s.secondsToNext, 150);
      // ~1112 m in 300 s ≈ 13.3 km/h
      expect(s.speed, 13);
    });

    test('stopped during the dwell, then moving towards the next stop', () {
      final dwell = engine.vehicleState(trip, 36320)!;
      expect(dwell.status, VehicleStatus.stopped);
      expect(dwell.currentStopId, 'b');
      expect(dwell.angle, 90); // b -> c is due east
      final leaving = engine.vehicleState(trip, 36331)!;
      expect(leaving.status, VehicleStatus.moving);
      expect(leaving.stopIndex, 1);
    });

    test('stopped at the terminus with nothing ahead', () {
      final s = engine.vehicleState(trip, 36600)!;
      expect(s.status, VehicleStatus.stopped);
      expect(s.stopIndex, 2);
      expect(s.nextStopId, isNull);
      expect(s.secondsToNext, 0);
      expect(s.progress, 1.0);
      expect(s.terminusArrival, 36600);
    });

    test('a moving vehicle between unknown places is not shown; a stopped one falls back', () {
      final ghost = _trip('g', ['a', 'zz'], [36000, 36300], [36000, 36300]);
      final e = TransitEngine([ghost], _places());
      expect(e.vehicleState(ghost, 36100), isNull);
      final atUnknown = e.vehicleState(ghost, 36300)!;
      expect(atUnknown.lat, 45.4642);
      expect(atUnknown.lon, 9.19);
    });

    test('zero running time between two stops: still at the first one, like the JS engine', () {
      // GTFS can give two consecutive stops the same minute: departure(b) == arrival(c).
      final quick = _trip('q', ['a', 'b', 'c'], [36000, 36300, 36300], [36000, 36300, 36400]);
      final e = TransitEngine([quick], _places());
      expect(e.vehicleState(quick, 36300)!.currentStopId, 'b');
      expect(e.vehicleState(quick, 36350)!.currentStopId, 'c');
    });

    test('single-stop trip', () {
      final one = _trip('one', ['a'], [36000], [36060]);
      final s = TransitEngine([one], _places()).vehicleState(one, 36030)!;
      expect(s.status, VehicleStatus.stopped);
      expect(s.progress, 1.0);
    });
  });

  group('activeVehicles', () {
    test('trips running past 27:00 show up early in the service day', () {
      final late = _trip('late', ['a', 'b'], [96000, 98000], [96000, 98000]);
      final engine = TransitEngine([late], _places());
      expect(engine.activeVehicles(96500).map((v) => v.tripId), ['late']);
      // 03:10 = 11,400 s; + 24 h = 97,800 s, still before the arrival at 98,000.
      final early = engine.activeVehicles(11400);
      expect(early.map((v) => v.tripId), ['late']);
      expect(early.single.secondsToNext, 200);
      expect(engine.activeVehicles(11700), isEmpty);
    });

    test('same vehicles as checking every trip (synthetic weekday metro)', () {
      final trips = newScheduler().generateMetroSchedule(DayType.weekday);
      final places = metroPlaces();
      final engines = [
        TransitEngine(trips, places),
        TransitEngine(trips, places, bucketSeconds: 37),
        TransitEngine(trips, places, bucketSeconds: 3600),
      ];
      for (var t = serviceDayStart; t < serviceDayEnd; t += 97) {
        final expected = _bruteForce(trips, t);
        for (final engine in engines) {
          expect(engine.activeVehicles(t).map((v) => v.tripId).toList(), expected, reason: 't=$t');
        }
      }
    });

    test('same vehicles as checking every trip (surface line 90, fractional times)', () {
      final trips = newScheduler().generateSurfaceSchedule('90', DayType.weekday);
      final engine = TransitEngine(trips, surfacePlaces());
      for (var t = serviceDayStart + 0.5; t < serviceDayEnd; t += 131.25) {
        expect(engine.activeVehicles(t).map((v) => v.tripId).toList(), _bruteForce(trips, t), reason: 't=$t');
      }
    });

    test('countActive filters by line', () {
      final trips = [
        _trip('x', ['a', 'b'], [36000, 36600], [36000, 36600], lineId: 'L1'),
        _trip('y', ['b', 'c'], [36000, 36600], [36000, 36600], lineId: 'L2'),
        _trip('z', ['a', 'c'], [36100, 36700], [36100, 36700], lineId: 'L1'),
      ];
      final engine = TransitEngine(trips, _places());
      expect(engine.countActive('L1', 36200), 2);
      expect(engine.countActive('L2', 36200), 1);
      expect(engine.countActive('L3', 36200), 0);
    });

    test('trips are kept sorted by start time, ties in input order', () {
      final trips = [
        _trip('second', ['a', 'b'], [36100, 36600], [36100, 36600]),
        _trip('tieA', ['a', 'b'], [36000, 36600], [36000, 36600]),
        _trip('tieB', ['a', 'b'], [36000, 36600], [36000, 36600]),
      ];
      final engine = TransitEngine(trips, _places());
      expect(engine.trips.map((t) => t.id), ['tieA', 'tieB', 'second']);
      expect(engine.activeVehicles(36200).map((v) => v.tripId), ['tieA', 'tieB', 'second']);
    });
  });

  group('departures', () {
    final places = _places();

    test('next trips, grouped by line and destination, limited per group', () {
      final trips = [
        for (var i = 0; i < 5; i++)
          _trip('c$i', ['a', 'b', 'c'], [36000 + i * 600, 36300 + i * 600, 36600 + i * 600],
              [36030 + i * 600, 36330 + i * 600, 36600 + i * 600]),
        _trip('r0', ['c', 'b', 'a'], [36100, 36400, 36700], [36100, 36400, 36700], to: 'A'),
      ];
      final engine = TransitEngine(trips, places);
      final board = engine.departures('b', 36000, perGroup: 2);
      expect(board.map((d) => d.trip.id), ['c0', 'r0', 'c1']);
      expect(board.first.waitSeconds, 300);
      expect(board.first.atPlatform, isFalse);
      expect(board.first.destination, 'C');
    });

    test('a vehicle at the stop has wait 0 and is at the platform', () {
      final trip = _trip('t', ['a', 'b', 'c'], [36000, 36300, 36600], [36000, 36330, 36600]);
      final board = TransitEngine([trip], places).departures('b', 36310);
      expect(board.single.waitSeconds, 0);
      expect(board.single.atPlatform, isTrue);
      expect(TransitEngine([trip], places).departures('b', 36331), isEmpty);
    });

    test('trips ending at the place are not departures', () {
      final trip = _trip('t', ['a', 'b', 'c'], [36000, 36300, 36600], [36000, 36330, 36600]);
      expect(TransitEngine([trip], places).departures('c', 36000), isEmpty);
    });

    test('horizon limits how far ahead the board looks', () {
      final trip = _trip('t', ['a', 'b'], [40000, 40300], [40000, 40300]);
      final engine = TransitEngine([trip], places);
      expect(engine.departures('a', 36000), isNotEmpty); // 4000 s < 7200 s
      expect(engine.departures('a', 36000, horizon: 3600), isEmpty);
    });

    test('early-morning boards include trips that run past 27:00', () {
      final late = _trip('late', ['a', 'b', 'c'], [96000, 97500, 98000], [96000, 97520, 98000]);
      final board = TransitEngine([late], places).departures('b', 11000);
      // 11,000 + 86,400 = 97,400: the arrival at b is 100 s later.
      expect(board.single.waitSeconds, 100);
      expect(board.single.arrivalTime, 97500 - secondsPerDay);
      expect(board.single.departureTime, 97520 - secondsPerDay);
    });

    test('only the first visit of a loop line counts', () {
      final loop = _trip('loop', ['a', 'b', 'a', 'c'], [36000, 36300, 36600, 36900], [36000, 36300, 36600, 36900]);
      final board = TransitEngine([loop], places).departures('a', 35000);
      expect(board.single.arrivalTime, 36000);
    });
  });
}
