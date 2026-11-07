import 'dart:math' as math;

/// Configuración centralizada de la aplicación.
/// El nombre definitivo se decidirá al final; se conserva [provisionalAppName]
/// centralizado para poder cambiarlo desde un único punto.
class AppConfig {
  const AppConfig._();

  static const String provisionalAppName = String.fromEnvironment(
    'APP_PROVISIONAL_NAME',
    defaultValue: 'NEXO',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Clave pública anónima de Supabase (nunca usar service_role en el cliente).
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String authRedirectUrl = 'pe.vecinos.app://auth-callback';

  static bool isAuthCallbackUri(Uri uri) {
    final callback = Uri.parse(authRedirectUrl);
    return uri.scheme == callback.scheme &&
        uri.host == callback.host &&
        uri.path == callback.path &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.trim().isNotEmpty &&
      supabaseAnonKey.trim().isNotEmpty &&
      !supabaseUrl.contains('example-project-ref');

  static bool get hasSupabaseCredentials => isSupabaseConfigured;
  static const String provisionalSubtitle = 'Tu comunidad, más cerca';
  static const double defaultLat = -12.076;
  static const double defaultLng = -77.063;
  static const zonesByDistrict = neighborhoodSectors;

  static const String defaultNeighborhood = String.fromEnvironment(
    'DEFAULT_NEIGHBORHOOD',
    defaultValue: 'Pueblo Libre',
  );

  static const String defaultSector = String.fromEnvironment(
    'DEFAULT_SECTOR',
    defaultValue: 'Sector San Martín',
  );

  /// Distritos y sectores disponibles (Pueblo Libre como escenario demo,
  /// sin limitar la arquitectura a un único distrito).
  static const Map<String, List<SectorZoneInfo>> neighborhoodSectors = {
    'Pueblo Libre': [
      SectorZoneInfo(
        neighborhood: 'Pueblo Libre',
        sector: 'Sector San Martín',
        publicLat: -12.076,
        publicLng: -77.063,
        referencePoint: 'Cerca de Parque San Martín / Plaza Bolívar',
      ),
      SectorZoneInfo(
        neighborhood: 'Pueblo Libre',
        sector: 'Sector Plaza Bolívar',
        publicLat: -12.077,
        publicLng: -77.063,
        referencePoint: 'Entorno Plaza Bolívar y Av. Gral. Vivanco',
      ),
      SectorZoneInfo(
        neighborhood: 'Pueblo Libre',
        sector: 'Sector Sucre / Candamo',
        publicLat: -12.074,
        publicLng: -77.065,
        referencePoint: 'Cuadrante Av. Sucre y Parque Candamo',
      ),
      SectorZoneInfo(
        neighborhood: 'Pueblo Libre',
        sector: 'Sector San Rafael',
        publicLat: -12.072,
        publicLng: -77.061,
        referencePoint: 'Alrededores del Parque San Rafael',
      ),
    ],
    'San Miguel': [
      SectorZoneInfo(
        neighborhood: 'San Miguel',
        sector: 'Sector Parque Media Luna',
        publicLat: -12.079,
        publicLng: -77.088,
        referencePoint: 'Entorno Parque Media Luna',
      ),
      SectorZoneInfo(
        neighborhood: 'San Miguel',
        sector: 'Sector Pando',
        publicLat: -12.071,
        publicLng: -77.081,
        referencePoint: 'Av. Universitaria / Pando',
      ),
    ],
    'Jesús María': [
      SectorZoneInfo(
        neighborhood: 'Jesús María',
        sector: 'Sector Plaza San José',
        publicLat: -12.075,
        publicLng: -77.048,
        referencePoint: 'Alrededores de Plaza San José',
      ),
      SectorZoneInfo(
        neighborhood: 'Jesús María',
        sector: 'Sector Residencial San Felipe',
        publicLat: -12.088,
        publicLng: -77.054,
        referencePoint: 'Áreas comunes de Residencial San Felipe',
      ),
    ],
    'Magdalena': [
      SectorZoneInfo(
        neighborhood: 'Magdalena',
        sector: 'Sector Plaza Túpac Amaru',
        publicLat: -12.091,
        publicLng: -77.070,
        referencePoint: 'Entorno de Plaza Túpac Amaru',
      ),
    ],
  };

  static SectorZoneInfo resolveZone(String neighborhood, String sector) {
    final sectors = neighborhoodSectors[neighborhood];
    if (sectors != null && sectors.isNotEmpty) {
      for (final item in sectors) {
        if (item.sector == sector) {
          return item;
        }
      }
      return sectors.first;
    }
    return SectorZoneInfo(
      neighborhood: neighborhood.trim().isEmpty
          ? defaultNeighborhood
          : neighborhood.trim(),
      sector: sector.trim().isEmpty ? defaultSector : sector.trim(),
      publicLat: -12.076,
      publicLng: -77.063,
      referencePoint: 'Zona aproximada seleccionada por el vecino',
    );
  }

  /// Redondea coordenadas a 3 decimales (~110 metros) para proteger la privacidad
  /// y no almacenar ni exponer jamás la ubicación exacta de una vivienda.
  static double roundPublicCoordinate(double value) {
    return (value * 1000.0).roundToDouble() / 1000.0;
  }

  static double? roundOptionalPublicCoordinate(double? value) =>
      value == null ? null : roundPublicCoordinate(value);

  /// Calcula la distancia aproximada en línea recta (en metros) y la redondea
  /// a múltiplos de 50 metros (mínimo 50 m) para evitar triangulación domiciliaria.
  static int approximateDistanceMeters({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const earthRadiusM = 6371000.0;
    final lat1 = roundPublicCoordinate(fromLat) * math.pi / 180.0;
    final lat2 = roundPublicCoordinate(toLat) * math.pi / 180.0;
    final dLat = lat2 - lat1;
    final dLng =
        (roundPublicCoordinate(toLng) - roundPublicCoordinate(fromLng)) *
        math.pi /
        180.0;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final rawDistance = earthRadiusM * c;
    final rounded50 = ((rawDistance / 50.0).round() * 50);
    return math.max(50, rounded50);
  }

  /// Formatea distancia aproximada en texto legible para personas mayores.
  static String formatApproximateDistance(int meters) {
    if (meters < 1000) {
      final blocks = math.max(1, (meters / 100).round());
      return 'Aprox. a $meters m (~$blocks ${blocks == 1 ? "cuadra" : "cuadras"})';
    }
    final km = (meters / 1000.0).toStringAsFixed(1);
    return 'Aprox. a $km km';
  }
}

class SectorZoneInfo {
  const SectorZoneInfo({
    required this.neighborhood,
    required this.sector,
    required this.publicLat,
    required this.publicLng,
    required this.referencePoint,
  });

  final String neighborhood;
  final String sector;
  final double publicLat;
  final double publicLng;
  final String referencePoint;
  String get district => neighborhood;
  double get centerLat => publicLat;
  double get centerLng => publicLng;
  String get referenceLandmark => referencePoint;
}

typedef NeighborhoodZone = SectorZoneInfo;
