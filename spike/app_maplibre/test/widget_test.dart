// Replaces the counter test that `flutter create` would generate. The map itself
// needs a platform view, so the behaviour is tested in map_spike_common.
import 'package:flutter_test/flutter_test.dart';
import 'package:map_spike_ml/main.dart';

void main() {
  test('backend reports its library', () {
    expect(MapLibreBackend().name, startsWith('maplibre'));
  });
}
