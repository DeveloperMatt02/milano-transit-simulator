import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

import 'support/data.dart';

void main() {
  final utils = golden['utils'] as Map<String, dynamic>;

  group('geo', () {
    test('haversine and bearing match the JS engine', () {
      for (final row in utils['geo'] as List<dynamic>) {
        final r = row as List<dynamic>;
        final a = metroNetwork.stations[r[0] as String]!;
        final b = metroNetwork.stations[r[1] as String]!;
        expect(haversine(a.lat, a.lon, b.lat, b.lon), closeTo((r[2] as num).toDouble(), 1e-6), reason: '$r');
        expect(bearing(a.lat, a.lon, b.lat, b.lon), r[3], reason: '$r');
      }
    });

    test('haversine: Duomo to Centrale is about 2.5 km', () {
      final d = haversine(45.4641, 9.1885, 45.4846, 9.2028);
      expect(d, inExclusiveRange(2400, 2600));
    });

    test('bearing: north is 0°, east is 90°', () {
      expect(bearing(45, 9, 46, 9), 0);
      expect(bearing(45, 9, 45, 10), 90);
    });

    test('jsRound rounds halves towards +infinity like Math.round', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect(jsRound(-2.6), -3);
    });
  });

  group('time', () {
    test('parseHHMM accepts service-day hours above 23', () {
      expect(parseHHMM('05:30'), 19800);
      expect(parseHHMM('25:15'), 25 * 3600 + 15 * 60);
      expect(parseHHMM('nope'), isNull);
      expect(parseHHMM(null), isNull);
    });

    test('toServiceTime maps early-morning clock times after 24:00', () {
      expect(toServiceTime(0), 24 * 3600);
      expect(toServiceTime(2.5 * 3600), 26.5 * 3600);
      expect(toServiceTime(3 * 3600), 3 * 3600);
      expect(toServiceTime(23 * 3600), 23 * 3600);
    });

    test('formatClock matches the JS engine', () {
      for (final row in utils['formatClock'] as List<dynamic>) {
        final r = row as List<dynamic>;
        expect(formatClock(r[0] as num), r[1]);
        expect(formatClock(r[0] as num, withSeconds: false), r[2]);
      }
    });

    test('isActiveAt handles trips that spill over the end of the service day', () {
      expect(isActiveAt(100, 200, 150), isTrue);
      expect(isActiveAt(100, 200, 250), isFalse);
      expect(isActiveAt(26 * 3600 + 50 * 60, 27 * 3600 + 40 * 60, 3 * 3600 + 10 * 60), isTrue);
    });
  });

  group('calendar', () {
    test('Easter Sunday 2000-2040 matches the JS engine', () {
      final easter = utils['easter'] as Map<String, dynamic>;
      for (final entry in easter.entries) {
        expect(easterSunday(int.parse(entry.key)).toIso(), entry.value, reason: entry.key);
      }
    });

    test('day types of every day of 2026 at 12:00 and 02:30 match the JS engine', () {
      String dayTypes(int hour, int minute) {
        final out = StringBuffer();
        for (var d = CivilDate(2026, 1, 1); d.year == 2026; d = d.addDays(1)) {
          final serviceDate = hour * 3600 + minute * 60 < serviceDayStart ? d.addDays(-1) : d;
          out.write(dayTypeForServiceDate(serviceDate).code);
        }
        return out.toString();
      }

      expect(dayTypes(12, 0), utils['dayTypes2026Noon']);
      expect(dayTypes(2, 30), utils['dayTypes2026At0230']);
    });

    test('holidays include Sant\'Ambrogio and Easter Monday', () {
      expect(dayTypeForServiceDate(CivilDate(2026, 9, 28)), DayType.weekday);
      expect(dayTypeForServiceDate(CivilDate(2026, 9, 26)), DayType.saturday);
      expect(dayTypeForServiceDate(CivilDate(2026, 9, 27)), DayType.holiday);
      expect(dayTypeForServiceDate(CivilDate(2026, 12, 7)), DayType.holiday);
      expect(dayTypeForServiceDate(CivilDate(2026, 4, 6)), DayType.holiday);
    });

    test('CivilDate arithmetic, comparison and parsing', () {
      final d = CivilDate.parse('2026-12-31');
      expect(d.addDays(1), CivilDate(2027, 1, 1));
      expect(CivilDate(2027, 3, 1).daysSince(CivilDate(2027, 2, 1)), 28);
      expect(CivilDate(2026, 3, 29).addDays(1).toIso(), '2026-03-30'); // across the DST change
      expect(d > CivilDate(2026, 1, 1), isTrue);
      expect({CivilDate(2026, 1, 1), CivilDate(2026, 1, 1)}, hasLength(1));
    });

    test('Milan wall clock (CET/CEST) matches the JS engine with the time-zone database', () {
      for (final row in utils['milanClock'] as List<dynamic>) {
        final r = row as List<dynamic>;
        final t = milanTime(DateTime.parse(r[0] as String));
        String two(int n) => n.toString().padLeft(2, '0');
        expect('${t.date.toIso()} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}', r[1], reason: r[0] as String);
      }
    });

    test('MilanTime gives the service date and day type before 03:00', () {
      // Monday 2026-09-28 at 02:59 Milan (00:59 UTC) is still Sunday's service.
      final t = milanTime(DateTime.utc(2026, 9, 28, 0, 59));
      expect(t.date, CivilDate(2026, 9, 28));
      expect(t.serviceDate, CivilDate(2026, 9, 27));
      expect(t.dayType, DayType.holiday);
      expect(t.serviceTime, closeTo(26 * 3600 + 59 * 60, 1e-9));
    });
  });
}
