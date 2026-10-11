// Behaviour of the synthetic scheduler, ported from tests/js/scheduler.test.js.
import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

void main() {
  final scheduler = newScheduler();
  final weekday = scheduler.generateMetroSchedule(DayType.weekday);

  test('time bands', () {
    expect(timeBand(6 * 3600), TimeBand.mid);
    expect(timeBand(8 * 3600), TimeBand.peak);
    expect(timeBand(12 * 3600), TimeBand.mid);
    expect(timeBand(18 * 3600), TimeBand.shoulder);
    expect(timeBand(21 * 3600), TimeBand.evening);
    expect(timeBand(24.5 * 3600), TimeBand.evening);
  });

  test('metro headways come from the open-data levels', () {
    final m3 = metroFrequencies['M3']!;
    expect(scheduler.headway('M3', 8 * 3600, DayType.weekday), m3[DayType.weekday]!.peakHeadway);
    expect(scheduler.headway('M3', 12 * 3600, DayType.weekday), m3[DayType.weekday]!.midHeadway);
    expect(scheduler.headway('M3', 23 * 3600, DayType.holiday), m3[DayType.holiday]!.eveningHeadway);
  });

  test('metro schedule is sorted and every trip has monotonic stop times', () {
    for (var i = 1; i < weekday.length; i++) {
      expect(weekday[i].startTime, greaterThanOrEqualTo(weekday[i - 1].startTime));
    }
    for (final trip in weekday) {
      for (var i = 0; i < trip.length; i++) {
        expect(trip.departures[i], greaterThanOrEqualTo(trip.arrivals[i]));
        if (i > 0) expect(trip.arrivals[i], greaterThan(trip.departures[i - 1]));
      }
    }
  });

  test('metro service window respects first departure and last arrival', () {
    for (final lineId in metroNetwork.lines.keys) {
      final trips = weekday.where((t) => t.lineId == lineId).toList();
      expect(trips.length, greaterThan(100), reason: lineId);
      final levels = metroFrequencies[lineId]![DayType.weekday]!;
      expect(trips.map((t) => t.startTime).reduce((a, b) => a < b ? a : b), parseHHMM(levels.firstDeparture));
      final lastEnd = trips.map((t) => t.endTime).reduce((a, b) => a > b ? a : b);
      expect(lastEnd, lessThanOrEqualTo(parseHHMM(levels.lastArrival)!));
      expect(lastEnd, greaterThan(24 * 3600), reason: '$lineId should run past midnight');
    }
  });

  test('M1 alternates the Bisceglie and Rho branches without duplicating Pagano', () {
    final fromSesto = weekday.where((t) => t.lineId == 'M1' && t.from == 'Sesto 1° Maggio').take(6).toList();
    expect(fromSesto.map((t) => t.to),
        ['Bisceglie', 'Rho Fieramilano', 'Bisceglie', 'Rho Fieramilano', 'Bisceglie', 'Rho Fieramilano']);
    expect(fromSesto[1].stopIds.where((id) => id == 'pagano'), hasLength(1));
  });

  test('fewer trips on Sundays than on weekdays', () {
    expect(scheduler.generateMetroSchedule(DayType.holiday).length, lessThan(weekday.length));
  });

  test('travel times are clamped between 50 s and 180 s', () {
    for (final line in metroNetwork.lines.values) {
      for (final path in line.paths.values) {
        for (var i = 0; i < path.length - 1; i++) {
          expect(scheduler.travelTime(path[i], path[i + 1]), inInclusiveRange(50, 180));
        }
      }
    }
  });

  test('surface routes without service on a day type produce no trips', () {
    final line = surfaceNetwork.lines.values.firstWhere(
      (l) => l.routes.every((r) => !r.frequencies.containsKey(DayType.holiday)),
    );
    expect(scheduler.generateSurfaceSchedule(line.id, DayType.holiday), isEmpty);
  });

  test('24-hour line 90 runs at 03:30', () {
    final trips = scheduler.generateSurfaceSchedule('90', DayType.weekday);
    expect(trips.any((t) => isActiveAt(t.startTime, t.endTime, 3.5 * 3600)), isTrue);
  });

  test('surface schedules are cached per line and day type', () {
    final a = scheduler.generateSurfaceSchedule('15', DayType.weekday);
    expect(identical(scheduler.generateSurfaceSchedule('15', DayType.weekday), a), isTrue);
    expect(identical(scheduler.generateSurfaceSchedule('15', DayType.saturday), a), isFalse);
  });

  test('route variants follow the JavaScript key order (integer keys ascending)', () {
    expect(jsKeyOrder(['9902', 'b', '9901', 'a', '10']), ['10', '9901', '9902', 'b', 'a']);
    expect(surfaceNetwork.lines['15']!.routes.map((r) => r.id), ['9901', '9902', '9903', '9904']);
  });
}
