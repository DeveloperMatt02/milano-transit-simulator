import 'dart:convert';
import 'dart:math' as math;

/// Distance in metres between two WGS84 points (equirectangular approximation,
/// accurate enough at city scale).
double distanceMeters(double lon1, double lat1, double lon2, double lat2) {
  const earthRadius = 6371000.0;
  const toRad = math.pi / 180;
  final x = (lon2 - lon1) * toRad * math.cos((lat1 + lat2) / 2 * toRad);
  final y = (lat2 - lat1) * toRad;
  return earthRadius * math.sqrt(x * x + y * y);
}

/// A polyline with cumulative distances, so a position can be found from the
/// distance travelled along it.
class LinePath {
  LinePath(List<(double, double)> points)
      : points = List.unmodifiable(points),
        cumulative = _cumulative(points) {
    if (points.length < 2) {
      throw ArgumentError.value(points.length, 'points', 'a path needs at least two points');
    }
  }

  /// (longitude, latitude) pairs.
  final List<(double, double)> points;

  /// Distance from the first point to point i, in metres.
  final List<double> cumulative;

  double get length => cumulative.last;

  static List<double> _cumulative(List<(double, double)> points) {
    final out = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final (lon1, lat1) = points[i - 1];
      final (lon2, lat2) = points[i];
      out.add(out.last + distanceMeters(lon1, lat1, lon2, lat2));
    }
    return out;
  }

  /// Position after [distance] metres from the start, clamped to the path.
  (double, double) positionAt(double distance) {
    if (distance <= 0) return points.first;
    if (distance >= length) return points.last;
    // Binary search for the segment [lo, lo + 1] that contains `distance`.
    var lo = 0;
    var hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = cumulative[hi] - cumulative[lo];
    final f = span == 0 ? 0.0 : (distance - cumulative[lo]) / span;
    final (lon1, lat1) = points[lo];
    final (lon2, lat2) = points[hi];
    return (lon1 + (lon2 - lon1) * f, lat1 + (lat2 - lat1) * f);
  }
}

class MetroLine {
  const MetroLine({required this.id, required this.color, required this.paths});

  final String id;

  /// CSS hex colour, e.g. `#E2231A`.
  final String color;
  final List<LinePath> paths;
}

class MetroNetwork {
  const MetroNetwork(this.lines);

  /// Parses `assets/metro_lines.json`: `{"lines": [{"id", "color", "paths": [[[lon, lat], ...]]}]}`.
  factory MetroNetwork.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final lines = <MetroLine>[];
    for (final raw in data['lines'] as List<dynamic>) {
      final line = raw as Map<String, dynamic>;
      final paths = <LinePath>[];
      for (final rawPath in line['paths'] as List<dynamic>) {
        final points = <(double, double)>[];
        for (final rawPoint in rawPath as List<dynamic>) {
          final point = rawPoint as List<dynamic>;
          points.add(((point[0] as num).toDouble(), (point[1] as num).toDouble()));
        }
        paths.add(LinePath(points));
      }
      lines.add(MetroLine(id: line['id'] as String, color: line['color'] as String, paths: paths));
    }
    return MetroNetwork(lines);
  }

  static const assetKey = 'packages/map_spike_common/assets/metro_lines.json';

  /// The lines as a GeoJSON FeatureCollection of LineStrings with a `c` (colour) property.
  Map<String, dynamic> linesGeoJson() {
    final features = <Map<String, dynamic>>[];
    for (final line in lines) {
      for (final path in line.paths) {
        features.add({
          'type': 'Feature',
          'id': features.length,
          'properties': {'line': line.id, 'c': line.color},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final (lon, lat) in path.points) [lon, lat],
            ],
          },
        });
      }
    }
    return {'type': 'FeatureCollection', 'features': features};
  }
}
