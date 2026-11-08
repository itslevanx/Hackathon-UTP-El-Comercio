import '../config/app_config.dart';

/// Parameters shared by requests, cache identities and explanatory labels.
class IntelligenceConfig {
  const IntelligenceConfig({
    this.radiusMeters = 300,
    this.windowMinutes = 15,
    this.minimumNeighbors = 3,
    this.compatibilityWeight = .40,
    this.distanceWeight = .25,
    this.availabilityWeight = .20,
    this.urgencyWeight = .15,
    this.distanceLimitMeters = 20000,
  });
  final double radiusMeters,
      compatibilityWeight,
      distanceWeight,
      availabilityWeight,
      urgencyWeight;
  final int windowMinutes, minimumNeighbors, distanceLimitMeters;
  String get fingerprint =>
      '$radiusMeters:$windowMinutes:$minimumNeighbors:'
      '$compatibilityWeight:$distanceWeight:$availabilityWeight:$urgencyWeight:$distanceLimitMeters';
  void validate() {
    final weights = [
      compatibilityWeight,
      distanceWeight,
      availabilityWeight,
      urgencyWeight,
    ];
    if (weights.any((w) => !w.isFinite || w < 0) ||
        (weights.reduce((a, b) => a + b) - 1).abs() > .00001 ||
        radiusMeters < 50 ||
        radiusMeters > 1000 ||
        !radiusMeters.isFinite ||
        windowMinutes < 1 ||
        windowMinutes > 60 ||
        minimumNeighbors < 3 ||
        minimumNeighbors > 20 ||
        distanceLimitMeters <= 0) {
      throw ArgumentError('Parámetros de inteligencia inválidos');
    }
  }
}

/// Stable identifiers, shared with community_resource_family in the migration.
/// Unknown legacy categories only match the exact same identifier.
class CommunityCategories {
  static const labels = <String, String>{
    'agua': 'Agua',
    'alimentos': 'Alimentos',
    'medicamentos': 'Medicamentos',
    'suministros': 'Suministros',
    'transporte': 'Transporte',
    'herramientas': 'Herramientas',
    'refugio': 'Refugio temporal',
    'acompanamiento': 'Acompañamiento',
    'primeros_auxilios_apoyo': 'Apoyo de primeros auxilios',
    'electricidad': 'Electricidad',
    'gasfiteria': 'Gasfitería',
    'incendio': 'Incendio',
    'inundacion': 'Inundación',
    'sismo': 'Sismo',
  };
  static String family(String category) => switch (category) {
    'agua_potable' => 'agua',
    'movilidad' => 'transporte',
    'albergue' => 'refugio',
    _ => category,
  };
  static String label(String category) =>
      labels[category] ?? category.replaceAll('_', ' ');
}

class RiskConcentration {
  RiskConcentration(this.data);
  final Map<String, dynamic> data;
  String get category => data['category'] as String;
  int get neighbors => (data['neighbors'] as num).toInt();
  bool get needsAttention => data['level'] == 'attention';
  double get lat => (data['lat'] as num).toDouble();
  double get lng => (data['lng'] as num).toDouble();
  List<String> get reportIds => List<String>.from(data['report_ids'] as List);
  DateTime get oldest => DateTime.parse(data['oldest'] as String);
  DateTime get newest => DateTime.parse(data['newest'] as String);
  String get label =>
      needsAttention ? 'Requiere atención' : 'Concentración detectada';
}

class HelpRecommendation {
  HelpRecommendation({
    required this.offer,
    required this.score,
    required this.distanceMeters,
    required this.explanations,
  });
  final Map<String, dynamic> offer;
  final double score;
  final int? distanceMeters;
  final List<String> explanations;
  String get id => offer['id'] as String;
}

class CommunityMatcher {
  CommunityMatcher([this.config = const IntelligenceConfig()]) {
    config.validate();
  }
  final IntelligenceConfig config;
  List<HelpRecommendation> rank(
    Map<String, dynamic> need,
    List<Map<String, dynamic>> offers,
  ) {
    if (need['author_id'] is! String ||
        (need['author_id'] as String).isEmpty ||
        need['category'] is! String ||
        need['district_ubigeo'] is! String ||
        !['favor_solicitud', 'emergencia_solicitud'].contains(need['kind']) ||
        need['deleted_at'] != null ||
        need['status'] != 'abierta') {
      return [];
    }
    final results = <HelpRecommendation>[];
    final seen = <String>{};
    for (final offer in offers) {
      if (offer['id'] is! String ||
          (offer['id'] as String).isEmpty ||
          offer['category'] is! String ||
          offer['author_id'] is! String ||
          (offer['author_id'] as String).isEmpty ||
          offer['district_ubigeo'] != need['district_ubigeo'] ||
          !seen.add(offer['id'] as String) ||
          offer['author_id'] == need['author_id'] ||
          offer['author_id'] == null ||
          offer['deleted_at'] != null ||
          offer['is_demo'] == true ||
          offer['status'] != 'abierta' ||
          ![
            'favor_oferta',
            'emergencia_oferta',
            'prestamo',
            'donacion',
            'habilidad',
            'servicio',
          ].contains(offer['kind']) ||
          (offer['kind'] == 'emergencia_oferta' &&
              offer['share_resource_consent'] != true) ||
          CommunityCategories.family(need['category'] as String) !=
              CommunityCategories.family(offer['category'] as String) ||
          ['general', 'donaciones', 'habilidades'].contains(need['category'])) {
        continue;
      }
      int? distance;
      final coords = [
        need['approx_lat'],
        need['approx_lng'],
        offer['approx_lat'],
        offer['approx_lng'],
      ];
      if (coords.every((v) => v is num && v.isFinite) &&
          (coords[0] as num).abs() <= 90 &&
          (coords[2] as num).abs() <= 90 &&
          (coords[1] as num).abs() <= 180 &&
          (coords[3] as num).abs() <= 180) {
        distance = AppConfig.approximateDistanceMeters(
          fromLat: (coords[0] as num).toDouble(),
          fromLng: (coords[1] as num).toDouble(),
          toLat: (coords[2] as num).toDouble(),
          toLng: (coords[3] as num).toDouble(),
        );
        if (distance > config.distanceLimitMeters) continue;
      } else if (need['district_ubigeo'] == null ||
          need['district_ubigeo'] != offer['district_ubigeo']) {
        continue;
      }
      final proximity = distance == null
          ? 0.0
          : (1 - distance / config.distanceLimitMeters).clamp(0.0, 1.0);
      // No schedule or stock can be inferred from free text. Open offers get
      // half the availability weight, explicitly requiring confirmation.
      final urgent = need['priority'] == 'emergencia'
          ? 1.0
          : need['priority'] == 'urgente'
          ? .5
          : 0.0;
      final score =
          100 *
          (config.compatibilityWeight +
              config.distanceWeight * proximity +
              config.availabilityWeight * .5 +
              config.urgencyWeight * urgent);
      results.add(
        HelpRecommendation(
          offer: offer,
          score: score,
          distanceMeters: distance,
          explanations: [
            'Misma categoría de recurso o servicio.',
            distance == null
                ? 'Sin coordenadas comparables; mismo distrito, sin puntaje por distancia.'
                : 'Cercanía aproximada: $distance m.',
            'Oferta abierta; horario y existencias por confirmar con el vecino.',
            if (urgent > 0) 'Prioridad de la solicitud: ${need['priority']}.',
            if (offer['kind'] == 'servicio' || offer['kind'] == 'habilidad') 'La recomendación no acredita capacitación ni autorización profesional.',
          ],
        ),
      );
    }
    results.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.id.compareTo(b.id);
    });
    return results;
  }
}
