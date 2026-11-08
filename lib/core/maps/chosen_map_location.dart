import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

class ChosenMapLocation {
  const ChosenMapLocation({
    required this.point,
    required this.districtUbigeo,
    this.shareExactService = false,
    this.address = '',
  });
  final LatLng point;
  final String districtUbigeo;
  final bool shareExactService;
  final String address;
  double get publicLat => AppConfig.roundPublicCoordinate(point.latitude);
  double get publicLng => AppConfig.roundPublicCoordinate(point.longitude);
  double? get serviceLat => shareExactService
      ? double.parse(point.latitude.toStringAsFixed(6))
      : null;
  double? get serviceLng => shareExactService
      ? double.parse(point.longitude.toStringAsFixed(6))
      : null;
  static ChosenMapLocation? tryFromMap(Map<String, dynamic> map) {
    final code = map['district_ubigeo'];
    final lat = (map['service_lat'] ?? map['approx_lat']) as num?;
    final lng = (map['service_lng'] ?? map['approx_lng']) as num?;
    if (code is! String ||
        !RegExp(r'^\d{6}$').hasMatch(code) ||
        lat == null ||
        lng == null) {
      return null;
    }
    if (!lat.isFinite ||
        !lng.isFinite ||
        lat < -85.05112878 ||
        lat > 85.05112878 ||
        lng < -180 ||
        lng > 180) {
      return null;
    }
    return ChosenMapLocation(
      point: LatLng(lat.toDouble(), lng.toDouble()),
      districtUbigeo: code,
      shareExactService: map['share_service_location'] == true,
      address: map['service_address'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() => {
    'district_ubigeo': districtUbigeo,
    'approx_lat': publicLat,
    'approx_lng': publicLng,
    'share_service_location': shareExactService,
    'service_lat': serviceLat,
    'service_lng': serviceLng,
    'service_address': shareExactService ? address.trim() : '',
  };
}
