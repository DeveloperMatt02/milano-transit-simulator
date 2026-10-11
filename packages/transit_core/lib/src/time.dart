/// Service-day time model (same as js/utils.js).
///
/// A *service day* runs from 03:00 to 03:00 of the next calendar day and times are seconds
/// from the midnight that opens it: 00:30 after midnight is 24:30 (88,200 s).
library;

const int secondsPerDay = 24 * 3600;
const int serviceDayStart = 3 * 3600; // 03:00
const int serviceDayEnd = serviceDayStart + secondsPerDay; // 27:00

final _hhmm = RegExp(r'^(\d{1,2}):(\d{2})$');

/// "HH:MM" (hours may exceed 23) -> seconds; null when invalid.
int? parseHHMM(String? value) {
  if (value == null) return null;
  final match = _hhmm.firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 3600 + int.parse(match.group(2)!) * 60;
}

/// Clock seconds after midnight -> service-day seconds (03:00 .. 26:59:59.999).
double toServiceTime(num clockSeconds) {
  final s = clockSeconds.toDouble() % secondsPerDay;
  return s < serviceDayStart ? s + secondsPerDay : s;
}

/// Service-day seconds -> "HH:MM:SS" (or "HH:MM") wall-clock text.
String formatClock(num seconds, {bool withSeconds = true}) {
  final s = seconds.floor() % secondsPerDay;
  String two(int n) => n.toString().padLeft(2, '0');
  final hh = two(s ~/ 3600);
  final mm = two((s % 3600) ~/ 60);
  return withSeconds ? '$hh:$mm:${two(s % 60)}' : '$hh:$mm';
}

/// True when a trip spanning [start, end] (service seconds) runs at service time [t],
/// including trips that spill past 27:00 into the next service day.
bool isActiveAt(num start, num end, num t) =>
    (t >= start && t <= end) || (t + secondsPerDay >= start && t + secondsPerDay <= end);
