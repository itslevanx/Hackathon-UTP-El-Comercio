import '../../core/geography/peru_location_catalog.dart';
import '../../core/models/domain_models.dart';

String normalizeVoiceText(String text) {
  const accents = 'áéíóúüñ';
  const simple = 'aeiouun';
  var result = text.toLowerCase();
  for (var i = 0; i < accents.length; i++) {
    result = result.replaceAll(accents[i], simple[i]);
  }
  return result
      .replaceAll(RegExp('[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

enum VoiceAttention { baja, media, alta, inmediata }

extension VoiceAttentionLabel on VoiceAttention {
  String get label => switch (this) {
    VoiceAttention.baja => 'Baja',
    VoiceAttention.media => 'Media',
    VoiceAttention.alta => 'Alta',
    VoiceAttention.inmediata => 'Atención inmediata',
  };
  PublicationPriority get publicationPriority => switch (this) {
    VoiceAttention.inmediata => PublicationPriority.emergencia,
    VoiceAttention.alta => PublicationPriority.urgente,
    _ => PublicationPriority.normal,
  };
}

class VoiceAnalysis {
  const VoiceAnalysis({
    required this.text,
    required this.category,
    required this.attention,
    required this.reasons,
    required this.districts,
    required this.resources,
    required this.quantities,
    required this.uncertain,
  });
  final String text, category;
  final VoiceAttention attention;
  final List<String> reasons, resources, quantities;
  final List<PeruLocationEntry> districts;
  final bool uncertain;
  bool get emergency =>
      [
        'sismo',
        'incendio',
        'inundacion',
        'derrumbe',
        'accidente',
      ].contains(category) ||
      attention == VoiceAttention.inmediata;
  PublicationKind get kind => emergency
      ? PublicationKind.emergenciaSolicitud
      : PublicationKind.favorSolicitud;
  List<String> get missing => [
    if (text.isEmpty) 'Descripción',
    if (category == 'general') 'Tipo de situación',
    if (districts.length != 1) 'Confirma el distrito',
    if (uncertain) 'Confirma lo que observaste',
  ];
}

class VoiceRules {
  const VoiceRules({
    this.criticalTerms = const [
      r'\batrapad[oa]s?\b',
      r'\bno respira\b',
      r'\bherid[oa]s? graves?\b',
      r'\bsangrado abundante\b',
    ],
    this.urgentTerms = const [
      r'\burgente\b',
      r'\bayuda inmediata\b',
      r'\bpersonas? en peligro\b',
    ],
  });
  final List<String> criticalTerms, urgentTerms;
}

class VoiceAnalyzer {
  VoiceAnalyzer(this.catalog, {this.rules = const VoiceRules()}) {
    for (final department in catalog.departments) {
      for (final province in catalog.provinces(department.code)) {
        for (final district in catalog.districts(province.code)) {
          final name = normalizeVoiceText(district.name);
          if (name.length < 3) continue;
          _districtNames.putIfAbsent(name, () => []).add(district);
          final words = name.split(' ').length;
          if (words > _maxDistrictWords) _maxDistrictWords = words;
        }
      }
    }
  }
  final Map<String, List<PeruLocationEntry>> _districtNames = {};
  int _maxDistrictWords = 1;
  final PeruLocationCatalog catalog;
  final VoiceRules rules;
  static const categories = <String, String>{
    'sismo': r'\b(sismo|cismo|temblor|terremoto|esta temblando)\b',
    'incendio': r'\b(incendio|fuego|se esta quemando)\b',
    'inundacion': r'\b(inundacion|inundando|inundada|aniego|huayco|desborde|desbordando)\b',
    'derrumbe': r'\b(derrumbe|derumbe|deslizamiento|se cayo el cerro)\b',
    'corte_servicios': r'\b(se fue la luz|sin luz|corte de (luz|agua|electricidad)|no hay (luz|agua)|se corto el agua)\b',
    'accidente': r'\b(accidente|choque|atropello|atropellad[oa])\b',
  };
  static const resourceTerms = <String, String>{
    'agua': r'\b(agua( potable)?|bidones?)\b',
    'alimentos': r'\b(alimentos?|comida|viveres|ollita comun|olla comun)\b',
    'medicamentos': r'\b(medicamentos?|medicinas?|botiquin)\b',
    'herramientas': r'\b(herramientas?|palas?|linternas?)\b',
    'transporte': r'\b(transporte|movilidad|traslado|llevar)\b',
    'refugio': r'\b(refugio|albergue|techo temporal)\b',
  };
  bool _positive(String text, String expression, {bool lackIsNeed = false}) {
    for (final match in RegExp(expression).allMatches(text)) {
      final prefix = text
          .substring(0, match.start)
          .split(RegExp(r'[.,;!?]|\bpero\b|\bsino\b|\by hay\b'))
          .last;
      if (lackIsNeed &&
          RegExp(
            r'\b(no (?:hay|tenemos|tengo|contamos con)|nos falta|falta|sin)\s*(?:suficiente\s*)?$',
          ).hasMatch(prefix)) {
        return true;
      }
      if (RegExp(
        r'\bno (?:hay|hubo|existen?|tengo|tenemos|se reportan?)\b(?:\s+\w+){0,5}\s*$',
      ).hasMatch(prefix)) {
        continue;
      }
      if (RegExp(
        r'\bno (?:necesito|necesitamos|requiero|queremos|necesita)\b.{0,50}$',
      ).hasMatch(prefix)) {
        continue;
      }
      if (RegExp(
        r'\b(no (?:hay|hubo|existe|es|necesito|necesitamos|estoy|estan|esta|tengo|tenemos)?\s*(?:ningun[oa]?\s*)?|sin indicios de\s*|sin\s*)$',
      ).hasMatch(prefix)) {
        continue;
      }
      return true;
    }
    return false;
  }

  VoiceAnalysis analyze(String source) {
    final text = normalizeVoiceText(source);
    final uncertain = RegExp(
      r'\b(creo|quizas|tal vez|parece|no estoy segur[oa]|posible)\b',
    ).hasMatch(text);
    final resources = resourceTerms.entries
        .where((e) => _positive(text, e.value, lackIsNeed: true))
        .map((e) => e.key)
        .toList();
    var category = 'general';
    for (final entry in categories.entries) {
      if (_positive(text, entry.value)) {
        category = entry.key;
        break;
      }
    }
    final critical = rules.criticalTerms.any((p) => _positive(text, p));
    final urgent = rules.urgentTerms.any((p) => _positive(text, p));
    if (category == 'general') {
      if (resources.isNotEmpty) {
        category = resources.first;
      } else if (critical ||
          _positive(text, r'\b(ayuda|asistencia|auxilio|apoyo|socorro)\b')) {
        category = 'asistencia';
      }
    }
    var attention = VoiceAttention.baja;
    final reasons = <String>[];
    if (critical || category == 'incendio') {
      attention = uncertain ? VoiceAttention.media : VoiceAttention.inmediata;
      reasons.add(
        'Se mencionan personas en riesgo o fuego; confirma la situación.',
      );
    } else if (urgent ||
        ['inundacion', 'derrumbe', 'accidente'].contains(category)) {
      attention = uncertain ? VoiceAttention.media : VoiceAttention.alta;
      reasons.add('Se menciona un riesgo o una necesidad urgente.');
    } else if (category != 'general') {
      attention = VoiceAttention.media;
      reasons.add(
        'Se describe una necesidad o situación que requiere coordinación.',
      );
    }
    if (uncertain) {
      reasons.add(
        'La descripción expresa incertidumbre; no confirma un incidente.',
      );
    }
    final mentions = <(PeruLocationEntry, int, int)>[];
    final tokens = RegExp(r'\b[a-z0-9]+\b').allMatches(text).toList();
    for (var start = 0; start < tokens.length; start++) {
      for (
        var end = start;
        end < tokens.length && end < start + _maxDistrictWords;
        end++
      ) {
        final name = text.substring(tokens[start].start, tokens[end].end);
        for (final district
            in _districtNames[name] ?? const <PeruLocationEntry>[]) {
          mentions.add((district, tokens[start].start, tokens[end].end));
        }
      }
    }
    final districts = mentions
        .where(
          (m) => !mentions.any(
            (other) =>
                other.$2 <= m.$2 &&
                other.$3 >= m.$3 &&
                other.$3 - other.$2 > m.$3 - m.$2,
          ),
        )
        .map((m) => m.$1)
        .toSet()
        .toList();
    final numbers = {
      'un': '1',
      'una': '1',
      'uno': '1',
      'dos': '2',
      'tres': '3',
      'cuatro': '4',
      'cinco': '5',
      'seis': '6',
      'siete': '7',
      'ocho': '8',
      'nueve': '9',
      'diez': '10',
    };
    final quantities =
        RegExp(
              r'\b(\d+(?:[.,]\d+)?|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez)\s+(litros?|bidones?|botellas?|kilos?|personas?|familias?|palas?)\b',
            )
            .allMatches(text)
            .map((m) => '${numbers[m.group(1)] ?? m.group(1)} ${m.group(2)}')
            .toList();
    return VoiceAnalysis(
      text: source.trim(),
      category: category,
      attention: attention,
      reasons: reasons,
      districts: districts,
      resources: resources,
      quantities: quantities,
      uncertain: uncertain,
    );
  }
}
