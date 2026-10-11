/// Timetable and simulation engine of Milano Transit Simulator.
///
/// Pure Dart (no Flutter): the Flutter app (F4) and the tests use the same code.
/// The behaviour of the synthetic timetable and of the simulation is checked against
/// the JavaScript engine of the Lite app (`test/parity_test.dart`).
library;

export 'src/calendar.dart';
export 'src/clock.dart';
export 'src/engine.dart';
export 'src/geo.dart';
export 'src/gtfs.dart';
export 'src/schedule.dart';
export 'src/synthetic.dart';
export 'src/time.dart';
export 'src/trip.dart';
