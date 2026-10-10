import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'fleet.dart';
import 'network.dart';
import 'rss_stub.dart' if (dart.library.io) 'rss_io.dart';
import 'stats.dart';

/// How often vehicle positions are pushed to the map.
enum UpdateMode {
  everyFrame('every frame'),
  tenHz('10 Hz');

  const UpdateMode(this.label);
  final String label;
}

const kVehicleCounts = [150, 300, 1000, 3000];

/// The go/no-go criterion of ADR 0001 is a 60 fps frame budget.
const kFrameBudgetMs = 1000 / 60;

/// One row of the benchmark table.
class BenchmarkResult {
  const BenchmarkResult({
    required this.vehicles,
    required this.mode,
    required this.tickP50,
    required this.tickP95,
    required this.slowTickShare,
    required this.updateP50,
    required this.updateP95,
    required this.buildP95,
    required this.rasterP95,
    required this.updatesSent,
    required this.updatesSkipped,
    required this.rssBytes,
  });

  final int vehicles;
  final UpdateMode mode;

  /// Interval between animation frames (vsync ticks) in ms.
  final double? tickP50;
  final double? tickP95;

  /// Share of ticks longer than [kFrameBudgetMs].
  final double? slowTickShare;

  /// Time for the map library to accept a new vehicles GeoJSON, in ms.
  final double? updateP50;
  final double? updateP95;

  /// Flutter's own frame phases (may not include the native map view).
  final double? buildP95;
  final double? rasterP95;
  final int updatesSent;

  /// Updates not sent because the previous one had not completed yet.
  final int updatesSkipped;
  final int? rssBytes;
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key, required this.backend});

  final MapBackend backend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map spike · ${backend.name}',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFE2231A)),
      home: SpikePage(backend: backend),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key, required this.backend, this.loadNetwork});

  final MapBackend backend;

  /// Overrides how the metro network is loaded (tests); defaults to the bundled asset.
  final Future<MetroNetwork> Function()? loadNetwork;

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> with SingleTickerProviderStateMixin {
  static const _warmUp = Duration(seconds: 3);
  static const _measure = Duration(seconds: 15);
  static const _tenHz = Duration(milliseconds: 100);

  late final Ticker _ticker = createTicker(_onTick);

  /// Built once: rebuilding the map widget every HUD refresh would distort the measurements.
  late final Widget _map = widget.backend.buildMap(context, onReady: _onMapReady);
  Timer? _hudTimer;

  MetroNetwork? _network;
  Fleet? _fleet;
  bool _mapReady = false;
  bool _started = false;
  String _status = 'Loading the metro lines…';
  String? _error;

  int _count = 300;
  UpdateMode _mode = UpdateMode.everyFrame;

  Duration? _lastTick;
  Duration _lastSent = Duration.zero;
  bool _updating = false;
  bool _recording = true;
  int _sent = 0;
  int _skipped = 0;
  final _tick = SampleStats();
  final _update = SampleStats();
  final _build = SampleStats();
  final _raster = SampleStats();

  bool _benchmarkRunning = false;
  final List<BenchmarkResult> _results = [];

  FlutterExceptionHandler? _previousFlutterOnError;
  bool Function(Object, StackTrace)? _previousPlatformOnError;
  Timer? _mapTimeout;

  /// Shows uncaught errors in the HUD: the spike runs on a phone without a debugger.
  void _reportError(Object error) {
    if (!mounted) return;
    setState(() => _error ??= error.toString().split('\n').first);
  }

  @override
  void initState() {
    super.initState();
    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _reportError(details.exception);
      _previousFlutterOnError?.call(details);
    };
    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _reportError(error);
      return _previousPlatformOnError?.call(error, stack) ?? false;
    };
    _mapTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted && !_mapReady) _reportError('the map did not report ready within 20 s');
    });
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _hudTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    FlutterError.onError = _previousFlutterOnError;
    PlatformDispatcher.instance.onError = _previousPlatformOnError;
    _mapTimeout?.cancel();
    _hudTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loader = widget.loadNetwork;
      final network = loader != null
          ? await loader()
          : MetroNetwork.fromJson(await rootBundle.loadString(MetroNetwork.assetKey));
      if (!mounted) return;
      setState(() {
        _network = network;
        _fleet = Fleet(network, _count);
        _status = 'Waiting for the map…';
      });
      await _maybeStart();
    } catch (error) {
      if (mounted) setState(() => _error = 'Cannot load the metro lines: $error');
    }
  }

  void _onMapReady() {
    if (_mapReady) return; // some libraries call it again when the style reloads
    _mapReady = true;
    unawaited(_maybeStart());
  }

  Future<void> _maybeStart() async {
    final network = _network;
    if (!_mapReady || network == null || _started) return;
    _started = true;
    try {
      await widget.backend.showLines(network.linesGeoJson());
    } catch (error) {
      if (mounted) setState(() => _error = 'Cannot add the layers: $error');
      return;
    }
    if (!mounted) return;
    _resetStats();
    // The TickerFuture only completes when the ticker stops: do not await it.
    unawaited(_ticker.start());
    setState(() => _status = 'Running');
  }

  // --------------------------------------------------------------------------- measuring

  void _onTick(Duration elapsed) {
    final fleet = _fleet;
    final last = _lastTick;
    _lastTick = elapsed;
    if (fleet == null || last == null) return;
    final dt = elapsed - last;
    if (_recording) _tick.add(dt.inMicroseconds / 1000);
    fleet.advance(dt.inMicroseconds / 1e6);

    final due = _mode == UpdateMode.everyFrame || elapsed - _lastSent >= _tenHz;
    if (!due) return;
    if (_updating) {
      if (_recording) _skipped++;
      return;
    }
    _lastSent = elapsed;
    unawaited(_sendUpdate(fleet));
  }

  Future<void> _sendUpdate(Fleet fleet) async {
    _updating = true;
    final watch = Stopwatch()..start();
    try {
      await widget.backend.updateVehicles(fleet.toGeoJson());
      if (_recording) {
        _update.add(watch.elapsedMicroseconds / 1000);
        _sent++;
      }
    } catch (error) {
      _error ??= 'Vehicle update failed: $error';
    } finally {
      _updating = false;
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_recording) return;
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
  }

  void _resetStats() {
    for (final s in [_tick, _update, _build, _raster]) {
      s.clear();
    }
    _sent = 0;
    _skipped = 0;
  }

  void _configure({int? count, UpdateMode? mode}) {
    final network = _network;
    setState(() {
      if (count != null && count != _count) {
        _count = count;
        if (network != null) _fleet = Fleet(network, count);
      }
      if (mode != null) _mode = mode;
      _resetStats();
    });
  }

  BenchmarkResult _snapshot() => BenchmarkResult(
        vehicles: _fleet?.length ?? 0,
        mode: _mode,
        tickP50: _tick.percentile(50),
        tickP95: _tick.percentile(95),
        slowTickShare: _tick.shareAbove(kFrameBudgetMs),
        updateP50: _update.percentile(50),
        updateP95: _update.percentile(95),
        buildP95: _build.percentile(95),
        rasterP95: _raster.percentile(95),
        updatesSent: _sent,
        updatesSkipped: _skipped,
        rssBytes: currentRssBytes(),
      );

  /// Every vehicle count × update mode: 3 s warm-up, 15 s measurement each (~2.5 min).
  Future<void> _runBenchmark() async {
    if (_benchmarkRunning || !_started) return;
    setState(() {
      _benchmarkRunning = true;
      _results.clear();
    });
    try {
      for (final count in kVehicleCounts) {
        for (final mode in UpdateMode.values) {
          if (!mounted) return;
          _recording = false;
          _configure(count: count, mode: mode);
          setState(() => _status = 'Warm-up · $count vehicles · ${mode.label}');
          await Future<void>.delayed(_warmUp);
          if (!mounted) return;
          _resetStats();
          _recording = true;
          setState(() => _status = 'Measuring · $count vehicles · ${mode.label}');
          await Future<void>.delayed(_measure);
          if (!mounted) return;
          _results.add(_snapshot());
        }
      }
      if (mounted) setState(() => _status = 'Benchmark done: press "Copy results"');
    } finally {
      _recording = true;
      if (mounted) setState(() => _benchmarkRunning = false);
    }
  }

  // --------------------------------------------------------------------------- results

  static String _ms(double? v) => v == null ? 'n/a' : v.toStringAsFixed(1);

  static String _pct(double? v) => v == null ? 'n/a' : '${(v * 100).toStringAsFixed(1)} %';

  static String _mb(int? bytes) => bytes == null ? 'n/a' : (bytes / (1024 * 1024)).toStringAsFixed(0);

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  String resultsText() {
    final rows = _results.isEmpty ? [_snapshot()] : _results;
    final out = StringBuffer()
      ..writeln('Map spike · ${widget.backend.name} · $_platform · ${DateTime.now().toIso8601String()}')
      ..writeln(_results.isEmpty ? '(live values, benchmark not run)' : '(benchmark: 3 s warm-up, 15 s per row)')
      ..writeln(_error == null ? '' : 'ERROR: $_error')
      ..writeln()
      ..writeln('| vehicles | mode | tick p50 ms | tick p95 ms | ticks > 16.7 ms | update p50 ms | update p95 ms '
          '| build p95 ms | raster p95 ms | updates sent | skipped | RSS MB |')
      ..writeln('|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (final r in rows) {
      out.writeln('| ${r.vehicles} | ${r.mode.label} | ${_ms(r.tickP50)} | ${_ms(r.tickP95)} | ${_pct(r.slowTickShare)} '
          '| ${_ms(r.updateP50)} | ${_ms(r.updateP95)} | ${_ms(r.buildP95)} | ${_ms(r.rasterP95)} '
          '| ${r.updatesSent} | ${r.updatesSkipped} | ${_mb(r.rssBytes)} |');
    }
    return out.toString();
  }

  Future<void> _copyResults() async {
    await Clipboard.setData(ClipboardData(text: resultsText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Results copied to the clipboard')));
  }

  // --------------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final live = _snapshot();
    final tickP50 = live.tickP50;
    final fps = tickP50 == null || tickP50 == 0 ? 'n/a' : (1000 / tickP50).toStringAsFixed(0);
    final lines = <String>[
      '${widget.backend.name} · $_platform',
      '$_count vehicles · ${_mode.label}',
      'tick p50/p95: ${_ms(live.tickP50)} / ${_ms(live.tickP95)} ms (≈ $fps fps)',
      'ticks > 16.7 ms: ${_pct(live.slowTickShare)}',
      'update p50/p95: ${_ms(live.updateP50)} / ${_ms(live.updateP95)} ms',
      'sent ${live.updatesSent} · skipped ${live.updatesSkipped}',
      'build/raster p95: ${_ms(live.buildP95)} / ${_ms(live.rasterP95)} ms',
      'RSS: ${_mb(live.rssBytes)} MB',
      _status,
      if (_error != null) 'ERROR: $_error',
    ];
    final locked = _benchmarkRunning || !_started;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _map),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Card(
                  color: Colors.white.withValues(alpha: 0.9),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      lines.join('\n'),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<int>(
                  segments: [
                    for (final n in kVehicleCounts) ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {_count},
                  showSelectedIcon: false,
                  onSelectionChanged: locked ? null : (s) => _configure(count: s.first),
                ),
                const SizedBox(height: 6),
                SegmentedButton<UpdateMode>(
                  segments: [
                    for (final m in UpdateMode.values) ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: locked ? null : (s) => _configure(mode: s.first),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: locked ? null : () => unawaited(_runBenchmark()),
                      child: const Text('Run benchmark'),
                    ),
                    OutlinedButton(
                      onPressed: () => unawaited(_copyResults()),
                      child: const Text('Copy results'),
                    ),
                    TextButton(
                      onPressed: locked ? null : () => setState(_resetStats),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
