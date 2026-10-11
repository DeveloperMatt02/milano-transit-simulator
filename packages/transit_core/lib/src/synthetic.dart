/// Synthetic timetable: the Dart port of js/scheduler.js.
///
/// The open data gives service levels (trips per time band, first and last run), not
/// stop-by-stop times. This scheduler turns them into a deterministic timetable and is the
/// fallback when the GTFS feed does not cover a line on a date (ADR 0002, ADR 0004).
library;

import 'dart:typed_data';

import 'calendar.dart';
import 'geo.dart';
import 'time.dart';
import 'trip.dart';

// ----------------------------------------------------------------------------------- data

class MetroStation {
  const MetroStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.lines,
    required this.interchanges,
  });

  factory MetroStation.fromJson(Map<String, dynamic> json) => MetroStation(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        lines: [for (final l in json['lines'] as List<dynamic>) l as String],
        interchanges: [for (final l in (json['interchanges'] as List<dynamic>? ?? const <dynamic>[])) l as String],
      );

  final String id;
  final String name;
  final double lat;
  final double lon;
  final List<String> lines;
  final List<String> interchanges;

  Place toPlace() => Place(id: id, name: name, lat: lat, lon: lon);
}

class MetroLineDef {
  const MetroLineDef({required this.id, required this.name, required this.color, required this.paths});

  factory MetroLineDef.fromJson(Map<String, dynamic> json) => MetroLineDef(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        color: json['color'] as String? ?? '#888888',
        paths: {
          for (final entry in (json['paths'] as Map<String, dynamic>).entries)
            entry.key: [for (final s in entry.value as List<dynamic>) s as String],
        },
      );

  final String id;
  final String name;
  final String color;

  /// Named station sequences in file order: `trunk`, `branch_*`.
  final Map<String, List<String>> paths;
}

/// The hand-written metro topology of js/data/metro-network.js.
class MetroNetwork {
  const MetroNetwork({required this.stations, required this.lines});

  factory MetroNetwork.fromJson(Map<String, dynamic> json) => MetroNetwork(
        stations: {
          for (final entry in (json['stations'] as Map<String, dynamic>).entries)
            entry.key: MetroStation.fromJson(entry.value as Map<String, dynamic>),
        },
        lines: {
          for (final entry in (json['lines'] as Map<String, dynamic>).entries)
            entry.key: MetroLineDef.fromJson(entry.value as Map<String, dynamic>),
        },
      );

  final Map<String, MetroStation> stations;
  final Map<String, MetroLineDef> lines;
}

/// Service levels of a line (metro) or route variant (surface) for one day type.
class ServiceLevels {
  const ServiceLevels({
    required this.peakHeadway,
    required this.midHeadway,
    required this.eveningHeadway,
    this.firstDeparture,
    this.lastArrival,
    this.serviceStart,
    this.serviceEnd,
  });

  factory ServiceLevels.fromJson(Map<String, dynamic> json) => ServiceLevels(
        peakHeadway: (json['peak_headway'] as num).toInt(),
        midHeadway: (json['mid_headway'] as num).toInt(),
        eveningHeadway: (json['evening_headway'] as num).toInt(),
        firstDeparture: json['first_departure'] as String?,
        lastArrival: json['last_arrival'] as String?,
        serviceStart: json['service_start'] as String?,
        serviceEnd: json['service_end'] as String?,
      );

  final int peakHeadway;
  final int midHeadway;
  final int eveningHeadway;

  /// Metro only ("HH:MM", hours may exceed 23).
  final String? firstDeparture;
  final String? lastArrival;

  /// Surface only ("HH:MM", hours may exceed 23).
  final String? serviceStart;
  final String? serviceEnd;
}

final _arrayIndex = RegExp(r'^(0|[1-9][0-9]{0,8})$');

/// Keys in JavaScript object iteration order: integer-like keys ("9901") first, ascending,
/// then the other keys in insertion order. The JSON files are written in insertion order,
/// but the JS engine iterates `Object.values(...)`; matching it keeps trip order identical.
List<String> jsKeyOrder(Iterable<String> keys) {
  final integers = <String>[];
  final others = <String>[];
  for (final key in keys) {
    (_arrayIndex.hasMatch(key) ? integers : others).add(key);
  }
  integers.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return [...integers, ...others];
}

Map<DayType, ServiceLevels> _levelsByDay(Map<String, dynamic> json) => {
      for (final entry in json.entries)
        DayType.fromCode(entry.key): ServiceLevels.fromJson(entry.value as Map<String, dynamic>),
    };

/// js/data/metro-frequencies.js: line -> day type -> levels.
Map<String, Map<DayType, ServiceLevels>> metroFrequenciesFromJson(Map<String, dynamic> json) => {
      for (final entry in json.entries) entry.key: _levelsByDay(entry.value as Map<String, dynamic>),
    };

class SurfaceStop {
  const SurfaceStop({required this.id, required this.name, required this.lat, required this.lon});

  final String id;
  final String name;
  final double lat;
  final double lon;

  Place toPlace() => Place(id: id, name: name, lat: lat, lon: lon);
}

class SurfaceRoute {
  const SurfaceRoute({required this.id, required this.stops, required this.frequencies});

  final String id;
  final List<String> stops;

  /// A missing day type means no service that day.
  final Map<DayType, ServiceLevels> frequencies;
}

class SurfaceLine {
  const SurfaceLine({required this.id, required this.mode, required this.color, required this.routes});

  final String id;
  final TransitMode mode;
  final String color;

  /// Route variants in file order.
  final List<SurfaceRoute> routes;
}

/// js/data/surface-network.js.
class SurfaceNetwork {
  const SurfaceNetwork({required this.stops, required this.lines});

  factory SurfaceNetwork.fromJson(Map<String, dynamic> json) {
    final stops = <String, SurfaceStop>{};
    for (final entry in (json['stations'] as Map<String, dynamic>).entries) {
      final s = entry.value as Map<String, dynamic>;
      stops[entry.key] = SurfaceStop(
        id: s['id'] as String,
        name: s['name'] as String,
        lat: (s['lat'] as num).toDouble(),
        lon: (s['lon'] as num).toDouble(),
      );
    }
    final lines = <String, SurfaceLine>{};
    final rawLines = json['lines'] as Map<String, dynamic>;
    for (final lineKey in jsKeyOrder(rawLines.keys)) {
      final l = rawLines[lineKey] as Map<String, dynamic>;
      final percorsi = l['percorsi'] as Map<String, dynamic>;
      lines[lineKey] = SurfaceLine(
        id: l['id'] as String,
        mode: TransitMode.fromCode(l['type'] as String),
        color: l['color'] as String? ?? '#1165B0',
        routes: [
          for (final routeKey in jsKeyOrder(percorsi.keys))
            _route(percorsi[routeKey] as Map<String, dynamic>),
        ],
      );
    }
    return SurfaceNetwork(stops: stops, lines: lines);
  }

  final Map<String, SurfaceStop> stops;
  final Map<String, SurfaceLine> lines;

  static SurfaceRoute _route(Map<String, dynamic> r) => SurfaceRoute(
        id: r['id'] as String,
        stops: [for (final s in r['stops'] as List<dynamic>) s as String],
        frequencies: _levelsByDay(r['frequencies'] as Map<String, dynamic>),
      );
}

// ------------------------------------------------------------------------------ scheduler

/// Time band of a service time: peak 07:00-09:30, off-peak 09:30-16:30,
/// shoulder 16:30-19:30, evening after 19:30, early morning = off-peak.
enum TimeBand { peak, mid, shoulder, evening }

TimeBand timeBand(num serviceSeconds) {
  final h = serviceSeconds / 3600;
  if (h >= 7 && h < 9.5) return TimeBand.peak;
  if (h >= 9.5 && h < 16.5) return TimeBand.mid;
  if (h >= 16.5 && h < 19.5) return TimeBand.shoulder;
  if (h >= 19.5) return TimeBand.evening;
  return TimeBand.mid;
}

int headwayFromLevels(ServiceLevels levels, num serviceSeconds) => switch (timeBand(serviceSeconds)) {
      TimeBand.peak => levels.peakHeadway,
      TimeBand.shoulder => jsRound((levels.peakHeadway + levels.midHeadway) / 2),
      TimeBand.evening => levels.eveningHeadway,
      TimeBand.mid => levels.midHeadway,
    };

class SyntheticScheduler {
  SyntheticScheduler(this.metro, {this.frequencies, this.surface});

  static const _metroDwellDefault = 25;
  static const _metroDwellInterchange = 45;
  static const _metroCruiseSpeed = 10.0; // m/s
  static const _metroMinRun = 50;
  static const _metroMaxRun = 180;
  static const _defaultFirstDeparture = 19800; // 05:30
  static const _defaultLastArrival = 88200; // 24:30

  static const _surfaceDwell = 15;
  static const _surfaceCruiseSpeed = 4.4; // m/s
  static const _surfaceMinRun = 20;
  static const _surfaceMaxRun = 200;

  final MetroNetwork metro;
  final Map<String, Map<DayType, ServiceLevels>>? frequencies;
  final SurfaceNetwork? surface;

  final Map<String, List<Trip>> _surfaceTripCache = {};
  final Map<String, List<int>> _surfaceDepartureCache = {};
  final Map<String, int> _surfaceDurationCache = {};

  // ------------------------------------------------------------------------------- metro

  int travelTime(String stationA, String stationB) {
    final a = metro.stations[stationA];
    final b = metro.stations[stationB];
    if (a == null || b == null) return 90;
    final t = jsRound(haversine(a.lat, a.lon, b.lat, b.lon) / _metroCruiseSpeed);
    return t.clamp(_metroMinRun, _metroMaxRun);
  }

  int dwellTime(String stationId) {
    final s = metro.stations[stationId];
    return s != null && s.interchanges.isNotEmpty ? _metroDwellInterchange : _metroDwellDefault;
  }

  /// Levels from the open data, or a conservative estimate when the line/day is missing.
  ServiceLevels metroLevels(String lineId, DayType dayType) {
    final official = frequencies?[lineId]?[dayType];
    if (official != null) return official;
    final weekend = dayType != DayType.weekday;
    return ServiceLevels(
      peakHeadway: weekend ? 360 : 180,
      midHeadway: weekend ? 360 : 300,
      eveningHeadway: 540,
      firstDeparture: dayType == DayType.holiday ? '06:00' : '05:30',
      lastArrival: '24:30',
    );
  }

  int headway(String lineId, num serviceSeconds, DayType dayType) =>
      headwayFromLevels(metroLevels(lineId, dayType), serviceSeconds);

  /// Every metro trip of a service day, sorted by start time.
  List<Trip> generateMetroSchedule(DayType dayType) {
    final trips = <Trip>[];
    for (final lineId in metro.lines.keys) {
      _generateLineTrips(lineId, dayType, trips);
    }
    return sortTripsByStart(trips);
  }

  void _generateLineTrips(String lineId, DayType dayType, List<Trip> out) {
    final line = metro.lines[lineId];
    if (line == null) return;
    final levels = metroLevels(lineId, dayType);
    final first = parseHHMM(levels.firstDeparture) ?? _defaultFirstDeparture;
    final lastArrival = parseHHMM(levels.lastArrival) ?? _defaultLastArrival;
    String name(String id) => metro.stations[id]!.name;

    final variants = _lineVariants(line);
    var t = first;
    var n = 0;
    while (t < lastArrival) {
      final (forward, backward) = variants(n);
      for (final (dir, path) in [('A', forward), ('B', backward)]) {
        final trip = createTrip(
          lineId: lineId,
          tripId: '$lineId-$dir-${n + 1}',
          from: name(path.first),
          to: name(path.last),
          stopIds: path,
          startTime: t,
          mode: TransitMode.metro,
          travel: travelTime,
          dwell: dwellTime,
        );
        if (trip.endTime <= lastArrival) out.add(trip);
      }
      t += headway(lineId, t, dayType);
      n++;
    }
  }

  /// n -> (forward, backward) station paths, alternating branches like ATM.
  (List<String>, List<String>) Function(int) _lineVariants(MetroLineDef line) {
    final p = line.paths;
    List<String> join(List<List<String>> segments) {
      final out = <String>[];
      for (final seg in segments) {
        out.addAll(out.isEmpty ? seg : seg.skip(1));
      }
      return out;
    }

    List<String> rev(List<String> list) => list.reversed.toList();

    final rho = p['branch_rho'];
    final bisceglie = p['branch_bisceglie'];
    if (rho != null && bisceglie != null) {
      // M1: Sesto 1° Maggio -> Pagano, then alternately Bisceglie / Rho Fieramilano.
      return (n) {
        final forward = join([p['trunk']!, n % 2 == 0 ? bisceglie : rho]);
        return (forward, rev(forward));
      };
    }
    final gessate = p['branch_gessate'];
    final cologno = p['branch_cologno'];
    final assago = p['branch_assago'];
    final abbiategrasso = p['branch_abbiategrasso'];
    if (gessate != null && cologno != null && assago != null && abbiategrasso != null) {
      // M2: north branches alternate; one train in three serves Assago in the south.
      return (n) {
        final north = n % 2 == 0 ? cologno : gessate;
        final south = n % 3 == 2 ? assago : abbiategrasso;
        final forward = join([north, p['trunk']!, south]);
        return (forward, rev(forward));
      };
    }
    final trunk = p['trunk']!;
    return (_) => (List.of(trunk), rev(trunk));
  }

  /// Builds a trip with arrival/departure times at every stop.
  Trip createTrip({
    required String lineId,
    required String tripId,
    required String from,
    required String to,
    required List<String> stopIds,
    required int startTime,
    required TransitMode mode,
    required int Function(String, String) travel,
    required int Function(String) dwell,
  }) {
    final arrivals = Int32List(stopIds.length);
    final departures = Int32List(stopIds.length);
    var clock = startTime;
    for (var i = 0; i < stopIds.length; i++) {
      final last = i == stopIds.length - 1;
      arrivals[i] = clock;
      departures[i] = last ? clock : clock + dwell(stopIds[i]);
      if (!last) clock = departures[i] + travel(stopIds[i], stopIds[i + 1]);
    }
    return Trip(
      id: tripId,
      lineId: lineId,
      mode: mode,
      from: from,
      to: to,
      stopIds: stopIds,
      arrivals: arrivals,
      departures: departures,
    );
  }

  // ----------------------------------------------------------------------------- surface

  SurfaceNetwork get _surface => surface ?? (throw StateError('no surface network'));

  int surfaceTravelTime(String stopA, String stopB) {
    final a = _surface.stops[stopA];
    final b = _surface.stops[stopB];
    if (a == null || b == null) return 60;
    final t = jsRound(haversine(a.lat, a.lon, b.lat, b.lon) / _surfaceCruiseSpeed);
    return t.clamp(_surfaceMinRun, _surfaceMaxRun);
  }

  /// Running time of a route from first to last stop (seconds).
  int surfaceRouteDuration(SurfaceRoute route) => _surfaceDurationCache.putIfAbsent(route.id, () {
        var duration = 0;
        for (var i = 0; i < route.stops.length - 1; i++) {
          duration += _surfaceDwell + surfaceTravelTime(route.stops[i], route.stops[i + 1]);
        }
        return duration;
      });

  /// Departures from the first stop of a route (service seconds); empty if it does not run.
  List<int> surfaceDepartures(SurfaceRoute route, DayType dayType) =>
      _surfaceDepartureCache.putIfAbsent('${route.id}|${dayType.code}', () {
        final levels = route.frequencies[dayType];
        final out = <int>[];
        if (levels != null) {
          final start = parseHHMM(levels.serviceStart);
          final end = parseHHMM(levels.serviceEnd);
          if (start != null && end != null) {
            for (var t = start; t <= end; t += headwayFromLevels(levels, t)) {
              out.add(t);
            }
          }
        }
        return out;
      });

  /// Stop-by-stop schedule of one surface line, cached per line and day type.
  List<Trip> generateSurfaceSchedule(String lineId, DayType dayType) =>
      _surfaceTripCache.putIfAbsent('$lineId|${dayType.code}', () {
        final line = _surface.lines[lineId];
        final trips = <Trip>[];
        if (line != null) {
          for (final route in line.routes) {
            final stops = route.stops;
            final from = _surface.stops[stops.first];
            final to = _surface.stops[stops.last];
            final departures = surfaceDepartures(route, dayType);
            for (var i = 0; i < departures.length; i++) {
              trips.add(createTrip(
                lineId: lineId,
                tripId: '$lineId-${route.id}-${i + 1}',
                from: from?.name ?? '',
                to: to?.name ?? '',
                stopIds: stops,
                startTime: departures[i],
                mode: line.mode,
                travel: surfaceTravelTime,
                dwell: (_) => _surfaceDwell,
              ));
            }
          }
        }
        return sortTripsByStart(trips);
      });

  /// Vehicles of a surface line on the road at service time [t], without building trips.
  int countActiveSurfaceVehicles(String lineId, DayType dayType, num t) {
    final line = _surface.lines[lineId];
    if (line == null) return 0;
    var count = 0;
    for (final route in line.routes) {
      final duration = surfaceRouteDuration(route);
      for (final d in surfaceDepartures(route, dayType)) {
        if (isActiveAt(d, d + duration, t)) count++;
      }
    }
    return count;
  }
}
