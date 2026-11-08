import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'carto_basemap.dart';

/// Lectura puntual y voluntaria. El punto redondeado solo centra el mapa;
/// no se guarda en el perfil ni se publica.
class MapLocationService {
  Future<LatLng?> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return approximateMapPoint(position.latitude, position.longitude);
  }
}
