// Micro-benchmark of the Dart engine hot paths (the Dart counterpart of
// tests/bench/engine.bench.js, F0 review finding H1).
//
//   dart run benchmark/engine_benchmark.dart           report only
//   dart run benchmark/engine_benchmark.dart --check   also fail when a budget is exceeded (CI)
//   dart run benchmark/engine_benchmark.dart --gtfs ../../data/gtfs   add the real GTFS network
//
// Cases: the synthetic weekday metro timetable copied 1×, 5× and 20× with small time offsets
// (the same illustrative volumes as the JS benchmark), and the whole synthetic network
// (metro + every surface line). Budgets are generous on purpose: CI machines are slow and
// noisy, the goal is to catch a return to "cost grows with every trip of the day".
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:transit_core/transit_core.dart';

const _at = 8.25 * 3600; // 08:15, weekday morning peak
const _station = 'duomo';
const _runs = 60;

/// Budgets (ms, p95) for the largest metro case (≈59,000 trips, ≈3,000 vehicles).
const _activeBudgetMs = 6.0;
const _boardBudgetMs = 2.0;

Map<String, dynamic> _readJsData(String name) {
  final text = File('../../js/data/$name').readAsStringSync();
  final start = text.indexOf('=', text.indexOf('const ')) + 1;
  final end = text.lastIndexOf('};') + 1;
  return jsonDecode(text.substring(start, end)) as Map<String, dynamic>;
}

class _Stats {
  _Stats(List<double> samples) : sorted = [...samples]..sort();
  final List<double> sorted;
  double _pick(double q) => sorted[(q * sorted.length).floor().clamp(0, sorted.length - 1)];
  double get min => sorted.first;
  double get median => _pick(0.5);
  double get p95 => _pick(0.95);
  @override
  String toString() =>
      '${median.toStringAsFixed(2)} (min ${min.toStringAsFixed(2)} · p95 ${p95.toStringAsFixed(2)})';
}

_Stats _measure(void Function() fn, [int runs = _runs]) {
  final watch = Stopwatch();
  final samples = <double>[];
  for (var i = 0; i < runs; i++) {
    watch
      ..reset()
      ..start();
    fn();
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  return _Stats(samples);
}

List<Trip> _scale(List<Trip> trips, int factor) => factor == 1
    ? trips
    : [
        for (var k = 0; k < factor; k++)
          for (final trip in trips) trip.shifted(k * 7, id: '${trip.id}#$k'),
      ];

void main(List<String> args) {
  final check = args.contains('--check');
  final scheduler = SyntheticScheduler(
    MetroNetwork.fromJson(_readJsData('metro-network.js')),
    frequencies: metroFrequenciesFromJson(_readJsData('metro-frequencies.js')),
    surface: SurfaceNetwork.fromJson(_readJsData('surface-network.js')),
  );
  final composer = ScheduleComposer(synthetic: scheduler);
  final places = composer.places();
  final metro = scheduler.generateMetroSchedule(DayType.weekday);

  final cases = <(String, List<Trip>, PlaceRegistry)>[
    for (final factor in const [1, 5, 20]) ('metro ×$factor', _scale(metro, factor), places),
    ('whole network (synthetic)', composer.compose(CivilDate(2026, 10, 5)).trips, places),
  ];
  final gtfsAt = args.indexOf('--gtfs');
  if (gtfsAt >= 0 && gtfsAt + 1 >= args.length) {
    stderr.writeln('--gtfs needs the directory of the GTFS datasets');
    exitCode = 2;
    return;
  }
  if (gtfsAt >= 0) {
    final dir = args[gtfsAt + 1];
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('$dir/$name').readAsStringSync()) as Map<String, dynamic>;
    final dataset = GtfsDataset.fromJson(network: read('network.json'), timetable: read('timetable.json'));
    final withGtfs = ScheduleComposer(synthetic: scheduler, gtfs: dataset);
    final buildDay = dataset.windowStart.addDays(1);
    final day = withGtfs.compose(buildDay);
    cases.add((
      'whole network, GTFS $buildDay (${day.estimatedLines.length} lines estimated)',
      day.trips,
      withGtfs.places(),
    ));
  }

  print('Dart engine benchmark — ${Platform.version.split(' ').first}, $_runs runs, 08:15 weekday');
  print('| case | trips | vehicles | index build ms | activeVehicles ms | departures($_station) ms |');
  print('|---|---|---|---|---|---|');
  final failures = <String>[];
  for (final (name, trips, casePlaces) in cases) {
    final build = _measure(() => TransitEngine(trips, casePlaces), 5);
    final engine = TransitEngine(trips, casePlaces);
    for (var i = 0; i < 20; i++) {
      engine
        ..activeVehicles(_at)
        ..departures(_station, _at);
    }
    final vehicles = engine.activeVehicles(_at).length;
    final active = _measure(() => engine.activeVehicles(_at));
    final board = _measure(() => engine.departures(_station, _at));
    print('| $name | ${trips.length} | $vehicles | ${build.median.toStringAsFixed(1)} | $active | $board |');
    if (name == 'metro ×20') {
      if (active.p95 > _activeBudgetMs) failures.add('activeVehicles p95 ${active.p95} ms > $_activeBudgetMs ms');
      if (board.p95 > _boardBudgetMs) failures.add('departures p95 ${board.p95} ms > $_boardBudgetMs ms');
    }
  }
  if (failures.isEmpty) {
    print('Budgets met (metro ×20: activeVehicles p95 ≤ $_activeBudgetMs ms, departures p95 ≤ $_boardBudgetMs ms).');
  } else {
    print('Budgets exceeded:\n  ${failures.join('\n  ')}');
    if (check) exitCode = 1;
  }
}
