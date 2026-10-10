import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_spike_common/map_spike_common.dart';

class _FakeBackend implements MapBackend {
  int linesShown = 0;
  int updates = 0;
  int lastVehicleCount = 0;

  @override
  String get name => 'fake';

  @override
  Widget buildMap(BuildContext context, {required VoidCallback onReady}) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
    return const ColoredBox(color: Colors.grey);
  }

  @override
  Future<void> showLines(Map<String, dynamic> linesGeoJson) async => linesShown++;

  @override
  Future<void> updateVehicles(Map<String, dynamic> vehiclesGeoJson) async {
    updates++;
    lastVehicleCount = (vehiclesGeoJson['features'] as List<dynamic>).length;
  }
}

final _network = MetroNetwork.fromJson('{"lines":[{"id":"M1","color":"#E2231A","paths":[[[9.18,45.46],[9.19,45.46]]]}]}');

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('shows the lines once, then streams vehicle updates', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: SpikePage(backend: backend, loadNetwork: () async => _network),
    ));
    await _pumpFrames(tester, 30);
    expect(backend.linesShown, 1);
    expect(backend.updates, greaterThan(10));
    expect(backend.lastVehicleCount, 300);
    expect(find.textContaining('fake'), findsOneWidget);

    // Switching to 10 Hz sends far fewer updates per frame.
    await tester.tap(find.text('10 Hz'));
    final before = backend.updates;
    await _pumpFrames(tester, 60); // ~1 s
    expect(backend.updates - before, inInclusiveRange(6, 12)); // 100 ms at 16 ms frames: 7 frames per update

    await tester.tap(find.text('1000'));
    await _pumpFrames(tester, 10);
    expect(backend.lastVehicleCount, 1000);

    await tester.pumpWidget(const SizedBox()); // dispose timers and ticker
  });
}
