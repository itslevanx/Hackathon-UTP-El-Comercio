import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import 'carto_basemap.dart';

/// Búsqueda puntual con el servicio del sistema operativo. No usa CARTO como
/// geocodificador ni el servidor público Nominatim; no registra direcciones.
class AddressLookupService {
  Future<List<LatLng>> search(String address, String area) async {
    final query = '${address.trim()}, $area, Perú';
    final values = await Geocoding(locale: const Locale('es', 'PE'))
        .locationFromAddress(query)
        .timeout(const Duration(seconds: 15));
    return values
        .where(
          (value) =>
              approximateMapPoint(value.latitude, value.longitude) != null,
        )
        .take(5)
        .map((value) => LatLng(value.latitude, value.longitude))
        .toList();
  }
}
