/// Simulation engine: vehicle positions and departure boards for one service day.
///
/// Same results as js/simulation-engine.js (checked by the parity tests), with indexes so the
/// cost no longer grows with the number of trips of the day (F0 review, finding H1):
/// - trips are bucketed by time (default 5 minutes), so a frame only visits candidate trips;
/// - every place has the list of (trip, stop) pairs that serve it, for departure boards;
/// - the position inside a trip is found by binary search.
library;

import 'geo.dart';
import 'time.dart';
import 'trip.dart';

enum VehicleStatus { stopped, moving }

class VehicleState {
  const VehicleState({
    required this.trip,
    required this.status,
    required this.stopIndex,
    required this.lat,
    required this.lon,
    required this.secondsToNext,
    required this.speed,
    required this.angle,
    required this.progress,
    required this.segmentProgress,
  });

  final Trip trip;
  final VehicleStatus status;

  /// Index in [Trip.stopIds] of the stop where the vehicle is, or that it has just left.
  final int stopIndex;
  final double lat;
  final double lon;

  /// Seconds until the arrival at the next stop (0 at the terminus).
  final num secondsToNext;

  /// Average speed of the current segment, km/h (0 when stopped).
  final int speed;

  /// Heading in degrees, 0 = north.
  final int angle;

  /// Share of the trip done (0..1) and of the current segment (0..1).
  final double progress;
  final double segmentProgress;

  String get tripId => trip.id;
  String get lineId => trip.lineId;
  String get currentStopId => trip.stopIds[stopIndex];
  String? get nextStopId => stopIndex + 1 < trip.length ? trip.stopIds[stopIndex + 1] : null;
  int get terminusArrival => trip.endTime;
}

class Departure {
  const Departure({
    required this.trip,
    required this.arrivalTime,
    required this.departureTime,
    required this.waitSeconds,
    required this.atPlatform,
  });

  final Trip trip;

  /// Service-day seconds of the board's day.
  final int arrivalTime;
  final int departureTime;
  final num waitSeconds;

  /// The vehicle is already at the stop.
  final bool atPlatform;

  String get lineId => trip.lineId;
  String get destination => trip.to;
}

const _fallbackLat = 45.4642;
const _fallbackLon = 9.19;

class TransitEngine {
  /// [trips] are sorted by start time if they are not already (stable).
  TransitEngine(List<Trip> trips, this.places, {this.bucketSeconds = 300})
      : assert(bucketSeconds > 0),
        trips = List.unmodifiable(sortTripsByStart(trips)) {
    _buildIndexes();
  }

  final List<Trip> trips;
  final PlaceRegistry places;
  final int bucketSeconds;

  final Map<int, List<int>> _buckets = {};

  /// place id -> (trip index, stop index) of the first visit of each trip, in trip order.
  final Map<String, List<(int, int)>> _visits = {};

  void _buildIndexes() {
    for (var i = 0; i < trips.length; i++) {
      final trip = trips[i];
      final first = trip.startTime ~/ bucketSeconds;
      final last = trip.endTime ~/ bucketSeconds;
      for (var b = first; b <= last; b++) {
        (_buckets[b] ??= <int>[]).add(i);
      }
      final seen = <String>{};
      for (var s = 0; s < trip.length; s++) {
        if (seen.add(trip.stopIds[s])) (_visits[trip.stopIds[s]] ??= <(int, int)>[]).add((i, s));
      }
    }
  }

  List<int> _candidates(num t) {
    final set = <int>{
      ...?_buckets[t.floor() ~/ bucketSeconds],
      ...?_buckets[(t + secondsPerDay).floor() ~/ bucketSeconds],
    };
    return set.toList()..sort();
  }

  /// Every vehicle running at service time [t], in trip order.
  List<VehicleState> activeVehicles(num t) {
    final out = <VehicleState>[];
    for (final i in _candidates(t)) {
      final trip = trips[i];
      num? effective;
      if (t >= trip.startTime && t <= trip.endTime) {
        effective = t;
      } else if (t + secondsPerDay >= trip.startTime && t + secondsPerDay <= trip.endTime) {
        effective = t + secondsPerDay;
      }
      if (effective == null) continue;
      final state = vehicleState(trip, effective);
      if (state != null) out.add(state);
    }
    return out;
  }

  /// Vehicles of one line running at [t].
  int countActive(String lineId, num t) => activeVehicles(t).where((v) => v.lineId == lineId).length;

  /// Position and status of [trip] at service time [t]; null when it is not running.
  ///
  /// Same rule as the linear scan of the JS engine: the first stop whose dwell contains [t]
  /// (stopped), otherwise the segment that contains it (moving). Departures never decrease
  /// along a trip, so the first stop with `departure >= t` is found by binary search.
  VehicleState? vehicleState(Trip trip, num t) {
    final n = trip.length;
    var lo = 0;
    var hi = n;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (trip.departures[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == n) return null; // after the arrival at the terminus
    final stoppedHere = trip.arrivals[lo] <= t;
    if (!stoppedHere && lo == 0) return null; // before the start
    // Stopped at `lo`, or moving between `lo - 1` and `lo`.
    final i = stoppedHere ? lo : lo - 1;
    final here = places[trip.stopIds[i]];
    final hasNext = i + 1 < n;
    final next = hasNext ? places[trip.stopIds[i + 1]] : null;

    if (stoppedHere) {
      return VehicleState(
        trip: trip,
        status: VehicleStatus.stopped,
        stopIndex: i,
        lat: here?.lat ?? _fallbackLat,
        lon: here?.lon ?? _fallbackLon,
        secondsToNext: hasNext ? trip.arrivals[i + 1] - t : 0,
        speed: 0,
        angle: here != null && next != null ? bearing(here.lat, here.lon, next.lat, next.lon) : 0,
        progress: n > 1 ? i / (n - 1) : 1.0,
        segmentProgress: 0,
      );
    }
    // Moving between `i` and `i + 1`: hidden when a place is unknown.
    if (here == null || next == null) return null;
    final departure = trip.departures[i];
    final duration = trip.arrivals[i + 1] - departure;
    final f = (t - departure) / duration;
    final distance = haversine(here.lat, here.lon, next.lat, next.lon);
    return VehicleState(
      trip: trip,
      status: VehicleStatus.moving,
      stopIndex: i,
      lat: here.lat + (next.lat - here.lat) * f,
      lon: here.lon + (next.lon - here.lon) * f,
      secondsToNext: trip.arrivals[i + 1] - t,
      speed: jsRound((distance / duration) * 3.6),
      angle: bearing(here.lat, here.lon, next.lat, next.lon),
      progress: (i + f) / (n - 1),
      segmentProgress: f.toDouble(),
    );
  }

  /// Next departures from a place, grouped by line and destination; trips ending there are
  /// excluded (a train arriving at its terminus does not depart).
  List<Departure> departures(String placeId, num t, {int perGroup = 3, int horizon = 7200}) {
    final results = <(int, Departure)>[];
    for (final (tripIndex, stopIndex) in _visits[placeId] ?? const <(int, int)>[]) {
      final trip = trips[tripIndex];
      if (stopIndex == trip.length - 1) continue;
      final arrival = trip.arrivals[stopIndex];
      final departure = trip.departures[stopIndex];
      for (final offset in const [0, secondsPerDay]) {
        final now = t + offset;
        if (departure >= now && arrival <= now + horizon) {
          final wait = arrival - now;
          results.add((
            tripIndex,
            Departure(
              trip: trip,
              arrivalTime: arrival - offset,
              departureTime: departure - offset,
              waitSeconds: wait < 0 ? 0 : wait,
              atPlatform: wait <= 0,
            ),
          ));
          break;
        }
      }
    }
    results.sort((a, b) {
      final byArrival = a.$2.arrivalTime.compareTo(b.$2.arrivalTime);
      return byArrival != 0 ? byArrival : a.$1.compareTo(b.$1);
    });
    final perKey = <String, int>{};
    final out = <Departure>[];
    for (final (_, d) in results) {
      final key = '${d.lineId}|${d.destination}';
      final seen = perKey[key] ?? 0;
      perKey[key] = seen + 1;
      if (seen < perGroup) out.add(d);
    }
    return out;
  }
}
