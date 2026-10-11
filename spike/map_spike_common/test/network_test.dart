import 'package:flutter_test/flutter_test.dart';
import 'package:map_spike_common/map_spike_common.dart';

const _json = '{"lines":[{"id":"M1","color":"#E2231A","paths":[[[9.18,45.46],[9.19,45.46],[9.19,45.47]]]},'
    '{"id":"M3","color":"#F5C400","paths":[[[9.20,45.45],[9.20,45.48]]]}]}';

void main() {
  test('distanceMeters matches the known size of a degree at Milan', () {
    // 0.01° of latitude ≈ 1112 m; 0.01° of longitude at 45.46° ≈ 780 m.
    expect(distanceMeters(9.19, 45.46, 9.19, 45.47), closeTo(1112, 2));
    expect(distanceMeters(9.18, 45.46, 9.19, 45.46), closeTo(780, 3));
  });

  test('LinePath interpolates by distance and clamps to its ends', () {
    final path = LinePath([(9.18, 45.46), (9.19, 45.46), (9.19, 45.47)]);
    expect(path.cumulative.first, 0);
    expect(path.length, closeTo(780 + 1112, 5));
    final (midLon, midLat) = path.positionAt(path.cumulative[1] / 2);
    expect(midLon, closeTo(9.185, 1e-9));
    expect(midLat, closeTo(45.46, 1e-9));
    expect(path.positionAt(-10), (9.18, 45.46));
    expect(path.positionAt(path.length + 10), (9.19, 45.47));
    final (_, lat) = path.positionAt(path.cumulative[1] + 1112 / 2);
    expect(lat, closeTo(45.465, 1e-4));
  });

  test('LinePath rejects paths with fewer than two points', () {
    expect(() => LinePath([(9.18, 45.46)]), throwsArgumentError);
  });

  test('MetroNetwork parses the asset format and exports GeoJSON lines', () {
    final network = MetroNetwork.fromJson(_json);
    expect(network.lines.map((l) => l.id), ['M1', 'M3']);
    final geojson = network.linesGeoJson();
    expect(geojson['type'], 'FeatureCollection');
    final features = geojson['features'] as List<Map<String, dynamic>>;
    expect(features, hasLength(2));
    expect((features.first['properties'] as Map<String, dynamic>)['c'], '#E2231A');
    final geometry = features.first['geometry'] as Map<String, dynamic>;
    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], [
      [9.18, 45.46],
      [9.19, 45.46],
      [9.19, 45.47],
    ]);
  });
}
