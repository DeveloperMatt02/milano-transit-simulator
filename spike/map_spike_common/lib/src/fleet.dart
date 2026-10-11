import 'dart:math' as math;

import 'network.dart';

/// One simulated vehicle running back and forth along a path.
class SimVehicle {
  SimVehicle({
    required this.line,
    required this.path,
    required this.distance,
    required this.direction,
    required this.speed,
  });

  final MetroLine line;
  final LinePath path;
  double distance;

  /// +1 towards the end of the path, -1 towards its start.
  int direction;

  /// Metres per second.
  final double speed;
}

/// A deterministic set of [count] vehicles spread over the network, proportionally
/// to the length of each path. Movement is synthetic: the spike measures rendering,
/// not the timetable engine.
class Fleet {
  Fleet(this.network, int count, {int seed = 42}) : vehicles = _spawn(network, count, seed);

  final MetroNetwork network;
  final List<SimVehicle> vehicles;

  int get length => vehicles.length;

  static List<SimVehicle> _spawn(MetroNetwork network, int count, int seed) {
    final random = math.Random(seed);
    final all = <(MetroLine, LinePath)>[
      for (final line in network.lines)
        for (final path in line.paths) (line, path),
    ];
    if (all.isEmpty || count <= 0) return [];
    final total = all.fold<double>(0, (sum, entry) => sum + entry.$2.length);
    final vehicles = <SimVehicle>[];
    for (var i = 0; i < count; i++) {
      // Pick a path with probability proportional to its length.
      var target = random.nextDouble() * total;
      var chosen = all.last;
      for (final entry in all) {
        target -= entry.$2.length;
        if (target <= 0) {
          chosen = entry;
          break;
        }
      }
      final (line, path) = chosen;
      vehicles.add(SimVehicle(
        line: line,
        path: path,
        distance: random.nextDouble() * path.length,
        direction: random.nextBool() ? 1 : -1,
        speed: 8 + random.nextDouble() * 6, // 29-50 km/h
      ));
    }
    return vehicles;
  }

  /// Moves every vehicle by [seconds] of simulated time, bouncing at the ends.
  void advance(double seconds) {
    for (final v in vehicles) {
      var d = v.distance + v.direction * v.speed * seconds;
      final length = v.path.length;
      if (d > length) {
        d = length - (d - length);
        v.direction = -1;
      } else if (d < 0) {
        d = -d;
        v.direction = 1;
      }
      v.distance = d.clamp(0, length).toDouble();
    }
  }

  /// Vehicle positions as a GeoJSON FeatureCollection of Points with a `c` (colour) property.
  Map<String, dynamic> toGeoJson() {
    final features = List<Map<String, dynamic>>.generate(vehicles.length, (i) {
      final v = vehicles[i];
      final (lon, lat) = v.path.positionAt(v.distance);
      return {
        'type': 'Feature',
        'id': i,
        'properties': {'c': v.line.color},
        'geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
      };
    }, growable: false);
    return {'type': 'FeatureCollection', 'features': features};
  }
}
