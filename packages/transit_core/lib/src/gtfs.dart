/// Reader of the GTFS datasets built by scripts/build_gtfs.py (format v1,
/// docs/TECHNICAL_DESIGN.md §9) and conversion of their trips into [Trip]s.
library;

import 'dart:typed_data';

import 'calendar.dart';
import 'geo.dart';
import 'time.dart';
import 'trip.dart';

class GtfsStop {
  const GtfsStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.wheelchair,
    required this.station,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// GTFS `wheelchair_boarding`: 0 unknown, 1 accessible, 2 not accessible.
  final int wheelchair;

  /// Metro station id (same ids as js/data/metro-network.js), null for surface stops.
  final String? station;

  /// The id trips use for this stop: the station for metro platforms, the stop otherwise.
  String get placeId => station ?? id;
}

class GtfsStation {
  const GtfsStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.lines,
    required this.stops,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final List<String> lines;

  /// Indices into [GtfsDataset.stops] (platforms of the station).
  final List<int> stops;
}

class GtfsRoute {
  const GtfsRoute({
    required this.id,
    required this.name,
    required this.longName,
    required this.mode,
    required this.color,
    required this.coverageEnd,
  });

  final String id;

  /// Line id used across the app: `M1` … `M5`, `15`, `90`, `N25`.
  final String name;
  final String longName;
  final TransitMode mode;
  final String? color;

  /// Last date with trips in the feed; after it the synthetic timetable is used (ADR 0004).
  final CivilDate? coverageEnd;
}

class GtfsPattern {
  const GtfsPattern({required this.route, required this.headsign, required this.stops, required this.shape});

  final int route;
  final String headsign;
  final Int32List stops;
  final int? shape;
}

class GtfsProfile {
  const GtfsProfile({required this.pattern, required this.arrivals, required this.dwells});

  final int pattern;

  /// Seconds from the trip start to the arrival at each stop.
  final Int32List arrivals;

  /// Dwell time at each stop; null when all are zero.
  final Int32List? dwells;
}

Int32List _ints(Object? json) => Int32List.fromList([for (final v in json! as List<dynamic>) (v as num).toInt()]);

void _checkVersion(Map<String, dynamic> json, String file) {
  final version = json['version'];
  if (version != GtfsDataset.formatVersion) {
    throw FormatException('$file: unsupported format version $version (expected ${GtfsDataset.formatVersion})');
  }
}

class GtfsDataset {
  GtfsDataset._({
    required this.stops,
    required this.stations,
    required this.routes,
    required this.patterns,
    required this.profiles,
    required this.windowStart,
    required this.windowDays,
    required this.services,
    required this.tripStart,
    required this.tripProfile,
    required this.tripService,
    required this.shapes,
    required this.shapePrecision,
    required this.meta,
  }) : _routesByName = {for (var i = 0; i < routes.length; i++) routes[i].name: i},
       _stationNames = {for (final s in stations) s.id: s.name};

  /// Parses the JSON documents (already decoded) of `network.json`, `timetable.json` and,
  /// optionally, `shapes.json` and `meta.json`.
  factory GtfsDataset.fromJson({
    required Map<String, dynamic> network,
    required Map<String, dynamic> timetable,
    Map<String, dynamic>? shapes,
    Map<String, dynamic>? meta,
  }) {
    _checkVersion(network, 'network.json');
    _checkVersion(timetable, 'timetable.json');
    if (shapes != null) _checkVersion(shapes, 'shapes.json');

    final stops = [
      for (final raw in network['stops'] as List<dynamic>)
        GtfsStop(
          id: (raw as Map<String, dynamic>)['id'] as String,
          name: raw['name'] as String,
          lat: (raw['lat'] as num).toDouble(),
          lon: (raw['lon'] as num).toDouble(),
          wheelchair: (raw['wheelchair'] as num?)?.toInt() ?? 0,
          station: raw['station'] as String?,
        ),
    ];
    final stations = [
      for (final raw in network['stations'] as List<dynamic>)
        GtfsStation(
          id: (raw as Map<String, dynamic>)['id'] as String,
          name: raw['name'] as String,
          lat: (raw['lat'] as num).toDouble(),
          lon: (raw['lon'] as num).toDouble(),
          lines: [for (final l in raw['lines'] as List<dynamic>) l as String],
          stops: [for (final s in raw['stops'] as List<dynamic>) (s as num).toInt()],
        ),
    ];
    final routes = [
      for (final raw in network['routes'] as List<dynamic>)
        GtfsRoute(
          id: (raw as Map<String, dynamic>)['id'] as String,
          name: raw['name'] as String,
          longName: raw['long_name'] as String? ?? '',
          mode: TransitMode.fromCode(raw['mode'] as String),
          color: raw['color'] as String?,
          coverageEnd: raw['coverage_end'] == null ? null : CivilDate.parse(raw['coverage_end'] as String),
        ),
    ];
    final patterns = [
      for (final raw in network['patterns'] as List<dynamic>)
        GtfsPattern(
          route: ((raw as Map<String, dynamic>)['route'] as num).toInt(),
          headsign: raw['headsign'] as String? ?? '',
          stops: _ints(raw['stops']),
          shape: (raw['shape'] as num?)?.toInt(),
        ),
    ];
    final profiles = [
      for (final raw in timetable['profiles'] as List<dynamic>)
        GtfsProfile(
          pattern: ((raw as Map<String, dynamic>)['pattern'] as num).toInt(),
          arrivals: _ints(raw['arrivals']),
          dwells: raw['dwells'] == null ? null : _ints(raw['dwells']),
        ),
    ];
    final window = timetable['window'] as Map<String, dynamic>;
    final trips = timetable['trips'] as Map<String, dynamic>;
    return GtfsDataset._(
      stops: stops,
      stations: stations,
      routes: routes,
      patterns: patterns,
      profiles: profiles,
      windowStart: CivilDate.parse(window['start'] as String),
      windowDays: (window['days'] as num).toInt(),
      services: [for (final m in timetable['services'] as List<dynamic>) (m as num).toInt()],
      tripStart: _ints(trips['start']),
      tripProfile: _ints(trips['profile']),
      tripService: _ints(trips['service']),
      shapes: [for (final s in (shapes?['shapes'] as List<dynamic>? ?? const <dynamic>[])) s as String],
      shapePrecision: (shapes?['precision'] as num?)?.toInt() ?? 5,
      meta: meta ?? const {},
    );
  }

  static const formatVersion = 1;

  final List<GtfsStop> stops;
  final List<GtfsStation> stations;
  final List<GtfsRoute> routes;
  final List<GtfsPattern> patterns;
  final List<GtfsProfile> profiles;
  final CivilDate windowStart;
  final int windowDays;

  /// Bit masks over the window days (bit i = window day i).
  final List<int> services;
  final Int32List tripStart;
  final Int32List tripProfile;
  final Int32List tripService;

  /// Encoded polylines (precision 5), indexed by [GtfsPattern.shape].
  final List<String> shapes;

  /// Decimal digits of the encoded polylines (`precision` in shapes.json).
  final int shapePrecision;
  final Map<String, dynamic> meta;
  final Map<String, int> _routesByName;
  final Map<String, String> _stationNames;

  /// Place ids of every pattern, shared by its trips.
  late final List<List<String>> _patternPlaceIds = [
    for (final p in patterns) List.unmodifiable([for (final s in p.stops) stops[s].placeId]),
  ];

  int get tripCount => tripStart.length;

  /// Last day of the window (inclusive).
  CivilDate get windowEnd => windowStart.addDays(windowDays - 1);

  /// Index of [date] in the window, or null outside it.
  int? dayIndex(CivilDate date) {
    final i = date.daysSince(windowStart);
    return i >= 0 && i < windowDays ? i : null;
  }

  GtfsRoute? route(String name) {
    final i = _routesByName[name];
    return i == null ? null : routes[i];
  }

  /// ADR 0004: GTFS times are authoritative for [routeName] on [date] only when the route is
  /// in the dataset, the date is inside the window and not after the route's coverage end.
  bool covers(String routeName, CivilDate date) {
    final r = route(routeName);
    if (r == null || dayIndex(date) == null) return false;
    final end = r.coverageEnd;
    return end == null || date <= end;
  }

  /// Metro stations and surface stops as places (metro platforms are merged into stations).
  Iterable<Place> get places sync* {
    for (final s in stations) {
      yield Place(id: s.id, name: s.name, lat: s.lat, lon: s.lon);
    }
    for (final s in stops) {
      if (s.station == null) yield Place(id: s.id, name: s.name, lat: s.lat, lon: s.lon);
    }
  }

  String _placeName(int stopIndex) {
    final stop = stops[stopIndex];
    return _stationNames[stop.station] ?? stop.name;
  }

  /// Trips of a service date on the service-day timeline (03:00 → 27:00):
  /// - trips of [date] starting at 03:00 or later, for the routes in [routes];
  /// - trips the feed dates to the next day but that start before 03:00 (night lines),
  ///   shifted by 24 h, for the routes in [nextDayRoutes] (default: [routes]).
  /// Trips of [date] that start before 03:00 belong to the previous service day.
  List<Trip> tripsOnServiceDate(CivilDate date, {required Set<String> routes, Set<String>? nextDayRoutes}) {
    final today = dayIndex(date);
    final tomorrow = dayIndex(date.addDays(1));
    final nextRoutes = nextDayRoutes ?? routes;
    final out = <Trip>[];
    for (var i = 0; i < tripCount; i++) {
      final profile = profiles[tripProfile[i]];
      final pattern = patterns[profile.pattern];
      final route = this.routes[pattern.route];
      final mask = services[tripService[i]];
      final start = tripStart[i];
      if (today != null && start >= serviceDayStart && (mask >> today) & 1 == 1 && routes.contains(route.name)) {
        out.add(_trip(i, route, pattern, profile, 0, ''));
      }
      if (tomorrow != null &&
          start < serviceDayStart &&
          (mask >> tomorrow) & 1 == 1 &&
          nextRoutes.contains(route.name)) {
        out.add(_trip(i, route, pattern, profile, secondsPerDay, '+1'));
      }
    }
    return sortTripsByStart(out);
  }

  Trip _trip(int index, GtfsRoute route, GtfsPattern pattern, GtfsProfile profile, int shift, String suffix) {
    final n = pattern.stops.length;
    final start = tripStart[index] + shift;
    final arrivals = Int32List(n);
    final departures = Int32List(n);
    final dwells = profile.dwells;
    for (var k = 0; k < n; k++) {
      arrivals[k] = start + profile.arrivals[k];
      departures[k] = arrivals[k] + (dwells == null ? 0 : dwells[k]);
    }
    final first = pattern.stops.first;
    final last = pattern.stops.last;
    return Trip(
      id: '${route.name}-g$index$suffix',
      lineId: route.name,
      mode: route.mode,
      from: _placeName(first),
      to: pattern.headsign.isNotEmpty ? pattern.headsign : _placeName(last),
      stopIds: _patternPlaceIds[profile.pattern],
      arrivals: arrivals,
      departures: departures,
    );
  }

  /// Decoded geometry of a shape as (lat, lon) points.
  List<(double, double)> shape(int index) => decodePolyline(shapes[index], precision: shapePrecision);
}

/// Google encoded polyline -> (lat, lon) points (same algorithm as build_gtfs.py).
List<(double, double)> decodePolyline(String encoded, {int precision = 5}) {
  final factor = _pow10(precision);
  final points = <(double, double)>[];
  var index = 0;
  var lat = 0;
  var lon = 0;
  while (index < encoded.length) {
    for (var coordinate = 0; coordinate < 2; coordinate++) {
      var shift = 0;
      var result = 0;
      while (true) {
        final byte = encoded.codeUnitAt(index) - 63;
        index++;
        result |= (byte & 0x1F) << shift;
        shift += 5;
        if (byte < 0x20) break;
      }
      final delta = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      if (coordinate == 0) {
        lat += delta;
      } else {
        lon += delta;
      }
    }
    points.add((lat / factor, lon / factor));
  }
  return points;
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}
