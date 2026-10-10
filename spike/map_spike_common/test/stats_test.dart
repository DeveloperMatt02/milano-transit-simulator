import 'package:flutter_test/flutter_test.dart';
import 'package:map_spike_common/map_spike_common.dart';

void main() {
  test('nearest-rank percentiles and share above a threshold', () {
    final stats = SampleStats();
    expect(stats.percentile(50), isNull);
    expect(stats.shareAbove(10), isNull);
    for (var i = 1; i <= 100; i++) {
      stats.add(i.toDouble());
    }
    expect(stats.percentile(50), 50);
    expect(stats.percentile(95), 95);
    expect(stats.percentile(100), 100);
    expect(stats.percentile(0), 1);
    expect(stats.shareAbove(90), closeTo(0.10, 1e-9));
    stats.clear();
    expect(stats.count, 0);
  });
}
