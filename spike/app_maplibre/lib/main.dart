import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:map_spike_common/map_spike_common.dart'
    show MapBackend, SpikeApp, kBaseStyle, kInitialZoom, kMilanLat, kMilanLon;
import 'package:maplibre/maplibre.dart';

void main() => runApp(SpikeApp(backend: MapLibreBackend()));

/// maplibre (josxha/flutter-maplibre): FFI/JNI on mobile, GeoJSON passed as a string.
class MapLibreBackend implements MapBackend {
  StyleController? _style;

  @override
  String get name => 'maplibre 0.3';

  @override
  Widget buildMap(BuildContext context, {required VoidCallback onReady}) {
    return MapLibreMap(
      options: const MapOptions(
        initStyle: kBaseStyle,
        initZoom: kInitialZoom,
        initCenter: Geographic(lon: kMilanLon, lat: kMilanLat),
      ),
      onStyleLoaded: (style) {
        _style = style;
        onReady();
      },
    );
  }

  @override
  Future<void> showLines(Map<String, dynamic> linesGeoJson) async {
    final style = _style!;
    await style.addSource(GeoJsonSource(id: 'lines', data: jsonEncode(linesGeoJson)));
    await style.addLayer(
      const LineStyleLayer(
        id: 'lines',
        sourceId: 'lines',
        paint: {
          'line-color': ['get', 'c'],
          'line-width': 4,
        },
        layout: {'line-cap': 'round', 'line-join': 'round'},
      ),
    );
    await style.addSource(const GeoJsonSource(id: 'vehicles', data: '{"type":"FeatureCollection","features":[]}'));
    await style.addLayer(
      const CircleStyleLayer(
        id: 'vehicles',
        sourceId: 'vehicles',
        paint: {
          'circle-color': ['get', 'c'],
          'circle-radius': 4,
          'circle-stroke-width': 1,
          'circle-stroke-color': '#FFFFFF',
        },
      ),
    );
  }

  @override
  Future<void> updateVehicles(Map<String, dynamic> vehiclesGeoJson) =>
      _style!.updateGeoJsonSource(id: 'vehicles', data: jsonEncode(vehiclesGeoJson));
}
