import 'dart:typed_data';

/// Means of transport, with the codes used by the datasets.
enum TransitMode {
  metro('METRO'),
  tram('TRAM'),
  trolleybus('FILOBUS'),
  bus('BUS');

  const TransitMode(this.code);
  final String code;

  static TransitMode fromCode(String code) =>
      values.firstWhere((m) => m.code == code, orElse: () => TransitMode.bus);
}

/// One run of a vehicle: the places it serves with arrival and departure times
/// (service-day seconds, strictly increasing between consecutive stops).
class Trip {
  Trip({
    required this.id,
    required this.lineId,
    required this.mode,
    required this.from,
    required this.to,
    required this.stopIds,
    required this.arrivals,
    required this.departures,
  }) : assert(stopIds.length == arrivals.length && arrivals.length == departures.length && stopIds.isNotEmpty);

  final String id;
  final String lineId;
  final TransitMode mode;

  /// Display names of the first and last place (or of the headsign).
  final String from;
  final String to;

  /// Metro station ids or surface stop ids.
  final List<String> stopIds;
  final Int32List arrivals;
  final Int32List departures;

  int get startTime => arrivals.first;

  /// Arrival at the terminus.
  int get endTime => arrivals.last;

  int get length => stopIds.length;

  /// The same trip moved by [seconds] (used to put next-day early trips on today's timeline).
  Trip shifted(int seconds, {String? id}) => Trip(
        id: id ?? this.id,
        lineId: lineId,
        mode: mode,
        from: from,
        to: to,
        stopIds: stopIds,
        arrivals: Int32List.fromList([for (final a in arrivals) a + seconds]),
        departures: Int32List.fromList([for (final d in departures) d + seconds]),
      );

  @override
  String toString() => 'Trip($id, $lineId, $from → $to, $startTime–$endTime)';
}

/// Sorts trips by start time keeping the original order of ties (like JavaScript's
/// stable `Array.prototype.sort`; Dart's `List.sort` is not guaranteed to be stable).
List<Trip> sortTripsByStart(List<Trip> trips) {
  final indexed = [for (var i = 0; i < trips.length; i++) (i, trips[i])];
  indexed.sort((a, b) {
    final byStart = a.$2.startTime.compareTo(b.$2.startTime);
    return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
