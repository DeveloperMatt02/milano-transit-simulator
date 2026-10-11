/// Timetable of a service day, line by line from GTFS or from the synthetic scheduler.
library;

import 'calendar.dart';
import 'geo.dart';
import 'gtfs.dart';
import 'synthetic.dart';
import 'trip.dart';

enum TimetableSource {
  /// Real planned times from the city's GTFS feed.
  gtfs,

  /// Estimated times from the open-data service levels (fallback).
  synthetic,

  /// No data for this line on this date.
  none,
}

class DailySchedule {
  const DailySchedule({required this.serviceDate, required this.dayType, required this.trips, required this.sources});

  final CivilDate serviceDate;
  final DayType dayType;

  /// Sorted by start time.
  final List<Trip> trips;

  /// Source used for each line.
  final Map<String, TimetableSource> sources;

  /// Lines shown with estimated times (for the "estimated times" notice).
  List<String> get estimatedLines => [
        for (final e in sources.entries)
          if (e.value == TimetableSource.synthetic) e.key,
      ];
}

/// Builds [DailySchedule]s applying the rule of ADR 0004 line by line and day by day.
class ScheduleComposer {
  ScheduleComposer({required this.synthetic, this.gtfs});

  final SyntheticScheduler synthetic;
  final GtfsDataset? gtfs;
  final Map<DayType, List<Trip>> _metroCache = {};

  /// Every line known to the synthetic networks or to the GTFS dataset.
  Set<String> get lineIds => {
        ...synthetic.metro.lines.keys,
        ...?synthetic.surface?.lines.keys,
        ...?gtfs?.routes.map((r) => r.name),
      };

  /// Places for the engine: synthetic metro stations and surface stops, then GTFS places.
  PlaceRegistry places() => PlaceRegistry()
    ..addAll(synthetic.metro.stations.values.map((s) => s.toPlace()))
    ..addAll(synthetic.surface?.stops.values.map((s) => s.toPlace()) ?? const <Place>[])
    ..addAll(gtfs?.places ?? const <Place>[]);

  DailySchedule compose(CivilDate serviceDate, {Iterable<String>? lines}) {
    final dayType = dayTypeForServiceDate(serviceDate);
    final wanted = lines?.toSet() ?? lineIds;
    final feed = gtfs;
    final sources = <String, TimetableSource>{};
    final trips = <Trip>[];

    final gtfsToday = <String>{};
    final gtfsTomorrow = <String>{};
    if (feed != null) {
      final tomorrow = serviceDate.addDays(1);
      for (final line in wanted) {
        if (!feed.covers(line, serviceDate)) continue;
        gtfsToday.add(line);
        // Night trips dated tomorrow (before 03:00) only when today is GTFS too: otherwise
        // the synthetic timetable already includes its own trips after midnight.
        if (feed.covers(line, tomorrow)) gtfsTomorrow.add(line);
      }
      if (gtfsToday.isNotEmpty) {
        trips.addAll(feed.tripsOnServiceDate(serviceDate, routes: gtfsToday, nextDayRoutes: gtfsTomorrow));
      }
    }

    for (final line in wanted) {
      if (gtfsToday.contains(line)) {
        sources[line] = TimetableSource.gtfs;
      } else if (synthetic.metro.lines.containsKey(line)) {
        sources[line] = TimetableSource.synthetic;
        final all = _metroCache.putIfAbsent(dayType, () => synthetic.generateMetroSchedule(dayType));
        trips.addAll(all.where((t) => t.lineId == line));
      } else if (synthetic.surface?.lines.containsKey(line) ?? false) {
        sources[line] = TimetableSource.synthetic;
        trips.addAll(synthetic.generateSurfaceSchedule(line, dayType));
      } else {
        sources[line] = TimetableSource.none;
      }
    }
    return DailySchedule(
      serviceDate: serviceDate,
      dayType: dayType,
      trips: sortTripsByStart(trips),
      sources: sources,
    );
  }
}
