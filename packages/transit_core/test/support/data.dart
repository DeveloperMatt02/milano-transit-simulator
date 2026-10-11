import 'dart:convert';
import 'dart:io';

import 'package:transit_core/transit_core.dart';

/// Tests run from the package root (`dart test`), two levels below the repository.
const repoRoot = '../..';

/// Reads a data file of the JS app (`const NAME = {...};`) as JSON.
Map<String, dynamic> readJsData(String name) {
  final text = File('$repoRoot/js/data/$name').readAsStringSync();
  final start = text.indexOf('=', text.indexOf('const ')) + 1;
  final end = text.lastIndexOf('};') + 1;
  return jsonDecode(text.substring(start, end)) as Map<String, dynamic>;
}

Map<String, dynamic> readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final metroNetwork = MetroNetwork.fromJson(readJsData('metro-network.js'));
final metroFrequencies = metroFrequenciesFromJson(readJsData('metro-frequencies.js'));
final surfaceNetwork = SurfaceNetwork.fromJson(readJsData('surface-network.js'));

SyntheticScheduler newScheduler() =>
    SyntheticScheduler(metroNetwork, frequencies: metroFrequencies, surface: surfaceNetwork);

PlaceRegistry metroPlaces() => PlaceRegistry()..addAll(metroNetwork.stations.values.map((s) => s.toPlace()));

PlaceRegistry surfacePlaces() => PlaceRegistry()..addAll(surfaceNetwork.stops.values.map((s) => s.toPlace()));

/// What js/ computes on fixed scenarios (tool/make_golden.js).
final golden = readJson('test/golden/js_engine.json');

/// GTFS fixture built from tests/python/fixtures/gtfs_mini (tool/make_fixtures.py).
GtfsDataset fixtureDataset({void Function(Map<String, dynamic> timetable)? editTimetable}) {
  const dir = 'test/fixtures/gtfs_mini';
  final timetable = readJson('$dir/timetable.json');
  editTimetable?.call(timetable);
  return GtfsDataset.fromJson(
    network: readJson('$dir/network.json'),
    timetable: timetable,
    shapes: readJson('$dir/shapes.json'),
    meta: readJson('$dir/meta.json'),
  );
}

/// A dataset written by scripts/build_gtfs.py into [dir] (network, timetable, shapes, meta).
GtfsDataset loadGtfsDir(String dir) {
  Map<String, dynamic>? optional(String name) {
    final file = File('$dir/$name');
    return file.existsSync() ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic> : null;
  }

  return GtfsDataset.fromJson(
    network: readJson('$dir/network.json'),
    timetable: readJson('$dir/timetable.json'),
    shapes: optional('shapes.json'),
    meta: optional('meta.json'),
  );
}

/// FNV-1a 32 bit over UTF-16 code units, like tool/make_golden.js.
int fnv1a(String text, [int hash = 0x811c9dc5]) {
  var h = hash;
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// The line of tool/make_golden.js `tripLine()` for a trip.
String tripLine(Trip trip) {
  final times = [for (var i = 0; i < trip.length; i++) '${trip.arrivals[i]}/${trip.departures[i]}'].join(',');
  return '${trip.id}|${trip.lineId}|${trip.mode.code}|${trip.from}|${trip.to}|${trip.stopIds.join(',')}|$times;';
}
