// ScheduleComposer: the per-line, per-day rule of ADR 0004.
import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

void main() {
  final scheduler = newScheduler();
  final monday = CivilDate(2026, 10, 5);
  const lines = ['M1', '15', '90', 'N25'];

  group('without GTFS', () {
    final composer = ScheduleComposer(synthetic: scheduler);

    test('every known line is synthetic, unknown lines have no data', () {
      final day = composer.compose(monday, lines: ['M1', '15', 'XYZ']);
      expect(day.sources, {
        'M1': TimetableSource.synthetic,
        '15': TimetableSource.synthetic,
        'XYZ': TimetableSource.none,
      });
      expect(day.estimatedLines, ['M1', '15']);
      expect(day.dayType, DayType.weekday);
    });

    test('same trips as the synthetic scheduler, sorted', () {
      final day = composer.compose(monday, lines: ['M1', '90']);
      final m1 = scheduler.generateMetroSchedule(DayType.weekday).where((t) => t.lineId == 'M1');
      final bus = scheduler.generateSurfaceSchedule('90', DayType.weekday);
      expect(day.trips.map((t) => t.id).toSet(), {...m1.map((t) => t.id), ...bus.map((t) => t.id)});
      expect(day.trips, hasLength(m1.length + bus.length));
      for (var i = 1; i < day.trips.length; i++) {
        expect(day.trips[i].startTime, greaterThanOrEqualTo(day.trips[i - 1].startTime));
      }
    });

    test('all lines by default; day type from the calendar', () {
      final day = composer.compose(CivilDate(2026, 12, 7)); // Sant'Ambrogio
      expect(day.dayType, DayType.holiday);
      expect(day.sources.keys.toSet(), composer.lineIds);
      expect(day.sources.values.toSet(), {TimetableSource.synthetic});
    });
  });

  group('with GTFS', () {
    final composer = ScheduleComposer(synthetic: scheduler, gtfs: fixtureDataset());

    test('lines and places from both sources', () {
      expect(composer.lineIds, containsAll(['M1', 'M5', '15', '90', 'N25']));
      final places = composer.places();
      expect(places['duomo'], isNotNull);
      expect(places['alfa'], isNotNull);
      expect(places['101'], isNotNull);
    });

    test('covered lines use GTFS', () {
      final day = composer.compose(monday, lines: lines);
      expect(day.sources.values.toSet(), {TimetableSource.gtfs});
      expect(day.estimatedLines, isEmpty);
      expect(day.trips.map((t) => t.id), ['M1-g0', 'M1-g1', '15-g2', '90-g5', 'N25-g6']);
    });

    test('after its coverage end a line falls back to the synthetic timetable', () {
      final day = composer.compose(CivilDate(2026, 10, 8), lines: lines);
      expect(day.sources['M1'], TimetableSource.gtfs);
      expect(day.sources['15'], TimetableSource.synthetic);
      expect(day.sources['N25'], TimetableSource.gtfs);
      expect(day.estimatedLines, ['15']);
      final tram = day.trips.where((t) => t.lineId == '15').toList();
      expect(tram, isNotEmpty);
      expect(tram.every((t) => !t.id.startsWith('15-g')), isTrue);
    });

    test('outside the window: synthetic where possible, otherwise no data', () {
      final day = composer.compose(CivilDate(2026, 10, 12), lines: lines);
      expect(day.sources, {
        'M1': TimetableSource.synthetic,
        '15': TimetableSource.synthetic,
        '90': TimetableSource.synthetic,
        'N25': TimetableSource.none,
      });
    });

    group('night trips dated the next day', () {
      final night = ScheduleComposer(
        synthetic: scheduler,
        gtfs: fixtureDataset(
          editTimetable: (t) => ((t['trips'] as Map<String, dynamic>)['start'] as List<dynamic>)[6] = 5400,
        ),
      );

      test('included once when both days are GTFS', () {
        final day = night.compose(monday, lines: ['N25']);
        expect(day.trips.map((t) => t.id), ['N25-g6+1']);
      });

      test('not added to a day that is not GTFS for the line', () {
        // 10-04 is before the window: N25 has no data that day, even though
        // the 01:30 trip of 10-05 would belong to it.
        final day = night.compose(CivilDate(2026, 10, 4), lines: ['N25']);
        expect(day.sources['N25'], TimetableSource.none);
        expect(day.trips, isEmpty);
      });

      test('not taken from a next day outside the coverage', () {
        final day = night.compose(CivilDate(2026, 10, 11), lines: ['N25']);
        expect(day.sources['N25'], TimetableSource.gtfs);
        expect(day.trips, isEmpty);
      });
    });
  });
}
