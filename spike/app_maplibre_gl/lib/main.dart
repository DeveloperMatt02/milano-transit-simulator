import 'package:flutter/material.dart';
import 'package:map_spike_common/map_spike_common.dart'
    show MapBackend, SpikeApp, kBaseStyle, kInitialZoom, kMilanLat, kMilanLon;
import 'package:maplibre_gl/maplibre_gl.dart';

void main() => runApp(SpikeApp(backend: MapLibreGlBackend()));

/// maplibre_gl (maplibre.org): method-channel plugin, GeoJSON passed as Dart maps.
class MapLibreGlBackend implements MapBackend {
  MapLibreMapController? _controller;

  @override
  String get name => 'maplibre_gl 0.27';

  @override
  Widget buildMap(BuildContext context, {required VoidCallback onReady}) {
    return MapLibreMap(
      styleString: kBaseStyle,
      initialCameraPosition: const CameraPosition(target: LatLng(kMilanLat, kMilanLon), zoom: kInitialZoom),
      compassEnabled: false,
      onMapCreated: (controller) => _controller = controller,
      onStyleLoadedCallback: onReady,
    );
  }

  @override
  Future<void> showLines(Map<String, dynamic> linesGeoJson) async {
    final controller = _controller!;
    await controller.addGeoJsonSource('lines', linesGeoJson);
    await controller.addLineLayer(
      'lines',
      'lines',
      const LineLayerProperties(
        lineColor: ['get', 'c'],
        lineWidth: 4,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await controller.addGeoJsonSource('vehicles', const {'type': 'FeatureCollection', 'features': <Object>[]});
    await controller.addCircleLayer(
      'vehicles',
      'vehicles',
      const CircleLayerProperties(
        circleColor: ['get', 'c'],
        circleRadius: 4,
        circleStrokeWidth: 1,
        circleStrokeColor: '#FFFFFF',
      ),
      enableInteraction: false,
    );
  }

  @override
  Future<void> updateVehicles(Map<String, dynamic> vehiclesGeoJson) =>
      _controller!.setGeoJsonSource('vehicles', vehiclesGeoJson);
}
