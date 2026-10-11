import 'dart:math' as math;

const _toRad = math.pi / 180;

/// `Math.round` of JavaScript: halves round towards +∞ (Dart's `round` goes away from zero).
int jsRound(num x) => (x + 0.5).floor();

/// Great-circle distance in metres between two WGS84 points (same formula as js/utils.js).
double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371e3;
  final dPhi = (lat2 - lat1) * _toRad;
  final dLambda = (lon2 - lon1) * _toRad;
  final sinPhi = math.sin(dPhi / 2);
  final sinLambda = math.sin(dLambda / 2);
  // Same grouping as the JS `cos * cos * sin ** 2`, so the rounding is identical.
  final a = sinPhi * sinPhi + math.cos(lat1 * _toRad) * math.cos(lat2 * _toRad) * (sinLambda * sinLambda);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Compass bearing in whole degrees (0 = north, clockwise), flat-earth approximation.
int bearing(double lat1, double lon1, double lat2, double lon2) {
  final dx = (lon2 - lon1) * math.cos(((lat1 + lat2) / 2) * _toRad);
  final dy = lat2 - lat1;
  return jsRound((math.atan2(dx, dy) * 180) / math.pi);
}

/// A named point: a metro station or a surface stop.
class Place {
  const Place({required this.id, required this.name, required this.lat, required this.lon});

  final String id;
  final String name;
  final double lat;
  final double lon;

  @override
  String toString() => 'Place($id, $name)';
}

/// Places by id; later additions do not replace existing entries.
class PlaceRegistry {
  final Map<String, Place> _places = {};

  Place? operator [](String id) => _places[id];

  int get length => _places.length;

  Iterable<Place> get all => _places.values;

  void add(Place place) => _places.putIfAbsent(place.id, () => place);

  void addAll(Iterable<Place> places) {
    for (final place in places) {
      add(place);
    }
  }
}
