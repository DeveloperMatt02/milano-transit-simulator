import 'package:flutter/widgets.dart';

/// OpenFreeMap Positron: the base map of the JS app in the Noorda light theme.
const kBaseStyle = 'https://tiles.openfreemap.org/styles/positron';

/// Centre of Milan (longitude, latitude) and the initial zoom of the spike map.
const kMilanLon = 9.19;
const kMilanLat = 45.4642;
const kInitialZoom = 11.0;

/// What each spike app implements with its map library.
abstract class MapBackend {
  /// Library name and version shown in the results, e.g. `maplibre_gl 0.27`.
  String get name;

  /// The map widget; [onReady] must be called once the style is loaded and
  /// sources/layers can be added.
  Widget buildMap(BuildContext context, {required VoidCallback onReady});

  /// Adds the static metro lines and an empty vehicles source with its layer.
  Future<void> showLines(Map<String, dynamic> linesGeoJson);

  /// Replaces the vehicle positions (the hot path being measured).
  Future<void> updateVehicles(Map<String, dynamic> vehiclesGeoJson);
}
