// The Dart engine must reproduce the JavaScript engine of the Lite app on fixed scenarios
// (test/golden/js_engine.json, written by tool/make_golden.js).
import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

void _expectSummary(List<Trip> trips, Map<String, dynamic> expected, String label) {
  expect(trips.length, expected['count'], reason: '$label: trip count');
  final perLine = <String, int>{};
  for (final t in trips) {
    perLine[t.lineId] = (perLine[t.lineId] ?? 0) + 1;
  }
  expect(perLine, expected['perLine'], reason: '$label: trips per line');
  final first = expected['first'] as List<dynamic>;
  for (var i = 0; i < first.length; i++) {
    final e = first[i] as List<dynamic>;
    final t = trips[i];
    expect([t.id, t.from, t.to, t.startTime, t.endTime, t.length], e, reason: '$label: trip #$i');
  }
  var hash = 0x811c9dc5;
  for (final t in trips) {
    hash = fnv1a(tripLine(t), hash);
  }
  expect(hash, expected['hash'], reason: '$label: hash of every stop time');
}

void _expectVehicles(List<VehicleState> actual, List<dynamic> expected, String label) {
  expect(actual.length, expected.length, reason: '$label: vehicle count');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as List<dynamic>;
    final v = actual[i];
    final where = '$label: vehicle #$i (${e[0]})';
    expect(v.tripId, e[0], reason: where);
    expect(v.status == VehicleStatus.stopped ? 'STOPPED' : 'MOVING', e[1], reason: where);
    expect(v.lat, closeTo((e[2] as num).toDouble(), 1e-9), reason: where);
    expect(v.lon, closeTo((e[3] as num).toDouble(), 1e-9), reason: where);
    expect(v.currentStopId, e[4], reason: where);
    expect(v.nextStopId, e[5], reason: where);
    expect(v.secondsToNext, closeTo((e[6] as num).toDouble(), 1e-6), reason: where);
    expect(v.speed, e[7], reason: where);
    expect(v.angle, e[8], reason: where);
    expect(v.progress, closeTo((e[9] as num).toDouble(), 1e-6), reason: where);
    expect(v.segmentProgress, closeTo((e[10] as num).toDouble(), 1e-6), reason: where);
  }
}

void _expectDepartures(List<Departure> actual, List<dynamic> expected, String label) {
  expect(actual.length, expected.length, reason: '$label: departures');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as List<dynamic>;
    final d = actual[i];
    expect([d.lineId, d.trip.id, d.destination, d.arrivalTime, d.departureTime], e.sublist(0, 5),
        reason: '$label: departure #$i');
    expect(d.waitSeconds, closeTo((e[5] as num).toDouble(), 1e-6), reason: '$label: departure #$i wait');
    expect(d.atPlatform, e[6], reason: '$label: departure #$i at platform');
  }
}

void main() {
  final scheduler = newScheduler();
  final metroGolden = golden['metro'] as Map<String, dynamic>;
  final metroTrips = {
    for (final dayType in DayType.values) dayType: scheduler.generateMetroSchedule(dayType),
  };

  group('metro timetable', () {
    for (final dayType in DayType.values) {
      test('day type ${dayType.code}', () {
        _expectSummary(metroTrips[dayType]!, metroGolden[dayType.code] as Map<String, dynamic>, 'metro ${dayType.code}');
      });
    }
  });

  group('surface timetable', () {
    final surfaceGolden = golden['surface'] as Map<String, dynamic>;
    for (final key in surfaceGolden.keys.where((k) => k.startsWith('schedule|'))) {
      test(key, () {
        final parts = key.split('|');
        final trips = scheduler.generateSurfaceSchedule(parts[2], DayType.fromCode(parts[1]));
        _expectSummary(trips, surfaceGolden[key] as Map<String, dynamic>, key);
      });
    }

    test('quick vehicle counts', () {
      for (final row in surfaceGolden['counts'] as List<dynamic>) {
        final r = row as List<dynamic>;
        expect(scheduler.countActiveSurfaceVehicles(r[0] as String, DayType.weekday, r[1] as num), r[2], reason: '$r');
      }
    });
  });

  group('vehicles and departure boards', () {
    final vehicles = golden['vehicles'] as Map<String, dynamic>;
    final departures = golden['departures'] as Map<String, dynamic>;
    final metroEngines = {
      for (final dayType in DayType.values) dayType: TransitEngine(metroTrips[dayType]!, metroPlaces()),
    };

    for (final key in vehicles.keys) {
      test('vehicles $key', () {
        final parts = key.split('|');
        final dayType = DayType.fromCode(parts[1]);
        if (parts[0] == 'metro') {
          final t = num.parse(parts[2]);
          _expectVehicles(metroEngines[dayType]!.activeVehicles(t), vehicles[key] as List<dynamic>, key);
        } else {
          final t = num.parse(parts[3]);
          final engine = TransitEngine(scheduler.generateSurfaceSchedule(parts[2], dayType), surfacePlaces());
          _expectVehicles(engine.activeVehicles(t), vehicles[key] as List<dynamic>, key);
        }
      });
    }

    for (final key in departures.keys) {
      test('departures $key', () {
        final parts = key.split('|');
        final dayType = DayType.fromCode(parts[1]);
        final t = num.parse(parts[2]);
        if (parts[0] == 'metro') {
          _expectDepartures(metroEngines[dayType]!.departures(parts[3], t), departures[key] as List<dynamic>, key);
        } else {
          final engine = TransitEngine(scheduler.generateSurfaceSchedule(parts[3], dayType), surfacePlaces());
          _expectDepartures(engine.departures(parts[4], t, perGroup: 2), departures[key] as List<dynamic>, key);
        }
      });
    }
  });
}
