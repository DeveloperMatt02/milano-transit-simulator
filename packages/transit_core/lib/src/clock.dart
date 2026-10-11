import 'calendar.dart';
import 'time.dart';

/// Simulation clock (port of the clock part of js/simulation-engine.js).
///
/// In real-time mode it follows Milan's wall clock; in manual mode it can be paused,
/// sped up (×1–×60) or moved, and wraps from 27:00 back to 03:00.
class SimulationClock {
  SimulationClock({DateTime Function()? now, double Function()? monotonicMs})
      : _now = now ?? DateTime.now,
        _monotonicMs = monotonicMs ?? _stopwatchMs {
    simTime = realServiceTime();
    _lastTick = _monotonicMs();
  }

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static double _stopwatchMs() => _stopwatch.elapsedMicroseconds / 1000;

  final DateTime Function() _now;
  final double Function() _monotonicMs;

  bool isRealTime = true;
  bool isPlaying = true;
  double speed = 1;
  late double simTime;
  late double _lastTick;

  /// Milan wall clock now.
  MilanTime get milanNow => milanTime(_now());

  /// Current wall-clock time on the service-day timeline.
  double realServiceTime() => milanNow.serviceTime;

  void setRealTimeMode(bool active) {
    isRealTime = active;
    if (active) {
      speed = 1;
      isPlaying = true;
      simTime = realServiceTime();
    }
    _lastTick = _monotonicMs();
  }

  /// Jumps to a service time (switches to manual mode).
  void setTime(num serviceSeconds) {
    isRealTime = false;
    simTime = wrap(serviceSeconds);
    _lastTick = _monotonicMs();
  }

  void setPlaying(bool playing) {
    if (!isRealTime) isPlaying = playing;
    _lastTick = _monotonicMs();
  }

  void setSpeed(double value) {
    if (!isRealTime) speed = value;
    _lastTick = _monotonicMs();
  }

  /// Keeps service time inside [03:00, 27:00).
  static double wrap(num t) {
    const span = serviceDayEnd - serviceDayStart;
    final r = (t - serviceDayStart) % span;
    // `-1e-12 % span` rounds up to `span` in floating point: that is 03:00, not 27:00.
    return (serviceDayStart + (r >= span ? 0 : r)).toDouble();
  }

  /// Advances the clock; returns true when the service day rolled over (27:00 -> 03:00).
  bool tick() {
    final now = _monotonicMs();
    final dt = (now - _lastTick) / 1000;
    _lastTick = now;
    final before = simTime;
    if (isRealTime) {
      simTime = realServiceTime();
    } else if (isPlaying) {
      simTime = wrap(simTime + dt * speed);
    }
    return simTime < before - 3600;
  }
}
