import 'time.dart';

/// A calendar date without time zone (year, month 1-12, day 1-31).
class CivilDate implements Comparable<CivilDate> {
  CivilDate(int year, int month, int day) : this._(DateTime.utc(year, month, day));

  CivilDate._(DateTime utc)
      : year = utc.year,
        month = utc.month,
        day = utc.day;

  /// Parses `YYYY-MM-DD`.
  factory CivilDate.parse(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) throw FormatException('expected YYYY-MM-DD', iso);
    return CivilDate(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// 1 = Monday … 7 = Sunday.
  int get weekday => _utc.weekday;

  CivilDate addDays(int days) => CivilDate._(_utc.add(Duration(days: days)));

  /// Whole days from [other] to this date.
  int daysSince(CivilDate other) => _utc.difference(other._utc).inDays;

  @override
  int compareTo(CivilDate other) => _utc.compareTo(other._utc);

  bool operator <(CivilDate other) => compareTo(other) < 0;
  bool operator <=(CivilDate other) => compareTo(other) <= 0;
  bool operator >(CivilDate other) => compareTo(other) > 0;
  bool operator >=(CivilDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is CivilDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  String toString() => toIso();
}

/// Timetable day type: weekday, Saturday, Sunday/holiday (codes of the open data).
enum DayType {
  weekday('L'),
  saturday('S'),
  holiday('F');

  const DayType(this.code);
  final String code;

  static DayType fromCode(String code) =>
      values.firstWhere((d) => d.code == code, orElse: () => throw ArgumentError.value(code, 'code'));
}

/// Easter Sunday (Gregorian calendar, anonymous algorithm).
CivilDate easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return CivilDate(year, month, day);
}

/// Fixed holidays as month * 100 + day.
const _fixedHolidays = {101, 106, 425, 501, 602, 815, 1101, 1207, 1208, 1225, 1226};

/// Italian national holidays plus Sant'Ambrogio (7 December), Milan's patron saint.
bool isMilanHoliday(CivilDate date) {
  if (_fixedHolidays.contains(date.month * 100 + date.day)) return true;
  return date == easterSunday(date.year).addDays(1); // Easter Monday
}

/// Day type of the timetable that runs on a service date.
DayType dayTypeForServiceDate(CivilDate date) {
  if (date.weekday == DateTime.sunday || isMilanHoliday(date)) return DayType.holiday;
  if (date.weekday == DateTime.saturday) return DayType.saturday;
  return DayType.weekday;
}

/// Wall-clock time in Milan: a calendar date and the seconds since its midnight.
class MilanTime {
  const MilanTime(this.date, this.secondOfDay);

  final CivilDate date;
  final double secondOfDay;

  int get hour => secondOfDay ~/ 3600;
  int get minute => (secondOfDay ~/ 60) % 60;
  int get second => secondOfDay.floor() % 60;

  /// Before 03:00 the previous calendar day's service is still running.
  CivilDate get serviceDate => secondOfDay < serviceDayStart ? date.addDays(-1) : date;

  /// Seconds on the service-day timeline (03:00 → 27:00) of [serviceDate].
  double get serviceTime => toServiceTime(secondOfDay);

  DayType get dayType => dayTypeForServiceDate(serviceDate);
}

DateTime _lastSundayUtc(int year, int month, int hour) {
  final lastDay = DateTime.utc(year, month + 1, 0); // day 0 of the next month
  return DateTime.utc(year, month, lastDay.day - lastDay.weekday % 7, hour);
}

/// Milan wall clock for an instant: CET (UTC+1) or CEST (UTC+2) with the EU rule
/// (summer time from 01:00 UTC on the last Sunday of March to 01:00 UTC on the last
/// Sunday of October). No time-zone database is needed.
MilanTime milanTime(DateTime instant) {
  final utc = instant.toUtc();
  final summer = !utc.isBefore(_lastSundayUtc(utc.year, 3, 1)) && utc.isBefore(_lastSundayUtc(utc.year, 10, 1));
  final local = utc.add(Duration(hours: summer ? 2 : 1));
  final seconds = local.hour * 3600 + local.minute * 60 + local.second + local.millisecond / 1000;
  return MilanTime(CivilDate(local.year, local.month, local.day), seconds);
}
