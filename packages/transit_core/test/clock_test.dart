import 'package:test/test.dart';
import 'package:transit_core/transit_core.dart';

void main() {
  test('wrap keeps time inside [03:00, 27:00)', () {
    expect(SimulationClock.wrap(10800), 10800);
    expect(SimulationClock.wrap(50000.5), 50000.5);
    expect(SimulationClock.wrap(97200), 10800);
    expect(SimulationClock.wrap(97300), 10900);
    expect(SimulationClock.wrap(10700), 97100);
    expect(SimulationClock.wrap(10800 - 1e-12), lessThan(97200));
  });

  group('real-time mode', () {
    test('follows the Milan wall clock (CEST)', () {
      final clock = SimulationClock(now: () => DateTime.utc(2026, 10, 10, 8));
      expect(clock.isRealTime, isTrue);
      expect(clock.simTime, 10 * 3600);
    });

    test('after midnight it stays on the previous service day', () {
      final clock = SimulationClock(now: () => DateTime.utc(2026, 10, 10, 22, 30));
      expect(clock.simTime, 24.5 * 3600);
      expect(clock.milanNow.serviceDate, CivilDate(2026, 10, 10));
      expect(clock.milanNow.dayType, DayType.saturday);
    });

    test('speed and pause are ignored', () {
      final clock = SimulationClock(now: () => DateTime.utc(2026, 1, 15, 11));
      clock
        ..setSpeed(10)
        ..setPlaying(false);
      expect(clock.speed, 1);
      expect(clock.isPlaying, isTrue);
      expect(clock.simTime, 12 * 3600); // CET, UTC+1
    });
  });

  group('manual mode', () {
    late double ms;
    late SimulationClock clock;
    setUp(() {
      ms = 0;
      clock = SimulationClock(now: () => DateTime.utc(2026, 10, 10, 8), monotonicMs: () => ms);
    });

    test('setTime switches to manual mode and the clock runs', () {
      clock.setTime(36000);
      expect(clock.isRealTime, isFalse);
      ms += 1000;
      expect(clock.tick(), isFalse);
      expect(clock.simTime, 36001);
    });

    test('speed multiplies, pause stops', () {
      clock
        ..setTime(36000)
        ..setSpeed(10);
      ms += 1000;
      clock.tick();
      expect(clock.simTime, 36010);
      clock.setPlaying(false);
      ms += 5000;
      clock.tick();
      expect(clock.simTime, 36010);
    });

    test('rolls over from 27:00 to 03:00', () {
      clock.setTime(97195);
      ms += 10000;
      expect(clock.tick(), isTrue);
      expect(clock.simTime, 10805);
    });

    test('back to real time resets speed and playback', () {
      clock
        ..setTime(50000)
        ..setSpeed(30)
        ..setPlaying(false)
        ..setRealTimeMode(true);
      expect(clock.speed, 1);
      expect(clock.isPlaying, isTrue);
      expect(clock.simTime, 36000);
    });
  });
}
