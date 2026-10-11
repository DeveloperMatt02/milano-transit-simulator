import 'package:flutter_test/flutter_test.dart';
import 'package:map_spike_common/map_spike_common.dart';

final _network = MetroNetwork.fromJson(
  '{"lines":[{"id":"M1","color":"#E2231A","paths":[[[9.18,45.46],[9.19,45.46]]]},'
  '{"id":"M3","color":"#F5C400","paths":[[[9.20,45.45],[9.20,45.48]]]}]}',
);

void main() {
  test('spawns the requested number of vehicles deterministically', () {
    final a = Fleet(_network, 300);
    final b = Fleet(_network, 300);
    expect(a.length, 300);
    expect(a.toGeoJson(), b.toGeoJson());
    expect(Fleet(_network, 0).length, 0);
  });

  test('longer paths get more vehicles', () {
    // The M3 path (~3.3 km) is about four times the M1 path (~0.8 km).
    final fleet = Fleet(_network, 2000);
    final m3 = fleet.vehicles.where((v) => v.line.id == 'M3').length;
    expect(m3 / fleet.length, closeTo(0.81, 0.05));
  });

  test('vehicles move at their speed and bounce at the ends of the path', () {
    final fleet = Fleet(_network, 50);
    final before = [for (final v in fleet.vehicles) v.distance];
    fleet.advance(1);
    for (var i = 0; i < fleet.length; i++) {
      final v = fleet.vehicles[i];
      expect(v.distance, inInclusiveRange(0, v.path.length));
      // Without a bounce the displacement equals the speed; with one it is shorter.
      expect((v.distance - before[i]).abs(), lessThanOrEqualTo(v.speed + 1e-9));
    }
    for (var i = 0; i < 2000; i++) {
      fleet.advance(1);
    }
    for (final v in fleet.vehicles) {
      expect(v.distance, inInclusiveRange(0, v.path.length));
    }
  });

  test('exports one GeoJSON point per vehicle with its line colour', () {
    final geojson = Fleet(_network, 10).toGeoJson();
    final features = geojson['features'] as List<Map<String, dynamic>>;
    expect(features, hasLength(10));
    for (final f in features) {
      expect((f['geometry'] as Map<String, dynamic>)['type'], 'Point');
      expect((f['properties'] as Map<String, dynamic>)['c'], anyOf('#E2231A', '#F5C400'));
    }
  });
}
