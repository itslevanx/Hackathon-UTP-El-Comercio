import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Un fallo antiguo o fuera de la vista no describe el mapa que se ve ahora.
class TileLoadHealth {
  final Map<TileCoordinates, bool> _results = {};
  bool? resultFor(TileCoordinates tile) => _results[tile];
  void record(TileCoordinates tile, bool loaded) {
    _results.remove(tile);
    _results[tile] = loaded;
    if (_results.length > 256) _results.remove(_results.keys.first);
  }

  void clear() => _results.clear();
  bool hasFailure(LatLngBounds bounds, double zoom) => _results.entries.any(
    (entry) => !entry.value && _visible(entry.key, bounds, zoom),
  );
  bool hasLoaded(LatLngBounds bounds, double zoom) => _results.entries.any(
    (entry) => entry.value && _visible(entry.key, bounds, zoom),
  );
  bool _visible(TileCoordinates tile, LatLngBounds bounds, double zoom) {
    if (tile.z != zoom.round().clamp(0, 18)) return false;
    final n = math.pow(2, tile.z).toDouble();
    double latitude(double y) {
      final value = math.pi * (1 - 2 * y / n);
      return math.atan((math.exp(value) - math.exp(-value)) / 2) *
          180 /
          math.pi;
    }

    final tileBounds = LatLngBounds(
      LatLng(latitude(tile.y + 1.0), tile.x / n * 360 - 180),
      LatLng(latitude(tile.y.toDouble()), (tile.x + 1) / n * 360 - 180),
    );
    return bounds.isOverlapping(tileBounds);
  }
}
