import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PeruLocationEntry {
  const PeruLocationEntry(
    this.code,
    this.name, {
    this.capitalLat,
    this.capitalLng,
  });
  final String code;
  final String name;
  final double? capitalLat;
  final double? capitalLng;
  String get departmentCode => code.substring(0, 2);
  String? get provinceCode => code.length >= 4 ? code.substring(0, 4) : null;
}

enum PeruLocationLevel { department, province, district }

class PeruLocationSelection {
  const PeruLocationSelection({
    this.departmentCode,
    this.provinceCode,
    this.districtCode,
  });
  const PeruLocationSelection.empty()
    : departmentCode = null,
      provinceCode = null,
      districtCode = null;
  final String? departmentCode;
  final String? provinceCode;
  final String? districtCode;

  @override
  bool operator ==(Object other) =>
      other is PeruLocationSelection &&
      departmentCode == other.departmentCode &&
      provinceCode == other.provinceCode &&
      districtCode == other.districtCode;
  @override
  int get hashCode => Object.hash(departmentCode, provinceCode, districtCode);
}

class PeruLocationCatalog {
  PeruLocationCatalog._(this.metadata, this._entries) {
    departments = _sorted(_entries.values.where((e) => e.code.length == 2));
    for (final entry in _entries.values) {
      if (entry.code.length == 4) {
        _provinces.putIfAbsent(entry.departmentCode, () => []).add(entry);
      } else if (entry.code.length == 6) {
        _districts.putIfAbsent(entry.provinceCode!, () => []).add(entry);
      }
    }
    for (final list in [..._provinces.values, ..._districts.values]) {
      list.sort(_compare);
    }
  }

  static Future<PeruLocationCatalog>? _bundled;
  static PeruLocationCatalog? _ready;
  static Future<PeruLocationCatalog> load() {
    if (_ready != null) return SynchronousFuture(_ready!);
    return _bundled ??= rootBundle
        .loadString('assets/geography/peru_ubigeo_2026.json')
        .then((source) => _ready = PeruLocationCatalog.fromJson(source));
  }

  factory PeruLocationCatalog.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final entries = <String, PeruLocationEntry>{};
    for (final (key, length) in [
      ('departments', 2),
      ('provinces', 4),
      ('districts', 6),
    ]) {
      for (final row in data[key] as List) {
        final values = row as List;
        final code = values[0] as String;
        if (!RegExp('^\\d{$length}\$').hasMatch(code) ||
            entries.containsKey(code)) {
          throw FormatException('Código UBIGEO inválido o duplicado: $code');
        }
        entries[code] = PeruLocationEntry(
          code,
          values[1] as String,
          capitalLat: values.length > 2 ? (values[2] as num).toDouble() : null,
          capitalLng: values.length > 3 ? (values[3] as num).toDouble() : null,
        );
      }
    }
    for (final code in entries.keys) {
      if (code.length > 2 &&
          !entries.containsKey(code.substring(0, code.length - 2))) {
        throw FormatException('UBIGEO sin padre: $code');
      }
    }
    return PeruLocationCatalog._(
      Map.unmodifiable(data['metadata'] as Map<String, dynamic>),
      Map.unmodifiable(entries),
    );
  }

  final Map<String, dynamic> metadata;
  final Map<String, PeruLocationEntry> _entries;
  final Map<String, List<PeruLocationEntry>> _provinces = {};
  final Map<String, List<PeruLocationEntry>> _districts = {};
  late final List<PeruLocationEntry> departments;

  PeruLocationEntry? entry(String? code) => _entries[code];
  PeruLocationEntry? district(String? code) =>
      code?.length == 6 ? entry(code) : null;
  List<PeruLocationEntry> provinces(String? department) =>
      List.unmodifiable(_provinces[department] ?? const []);
  List<PeruLocationEntry> districts(String? province) =>
      List.unmodifiable(_districts[province] ?? const []);

  // Solo los códigos de distrito completos y reconocidos restauran los tres niveles.
  // Los nombres heredados o códigos incompletos no se adivinan ni rellenan.
  PeruLocationSelection selectionForDistrict(String? code) {
    final found = district(code);
    return found == null
        ? const PeruLocationSelection.empty()
        : PeruLocationSelection(
            departmentCode: found.departmentCode,
            provinceCode: found.provinceCode,
            districtCode: found.code,
          );
  }

  PeruLocationSelection normalize(PeruLocationSelection value) {
    final dep = entry(value.departmentCode);
    if (dep == null || dep.code.length != 2) {
      return const PeruLocationSelection.empty();
    }
    final prov = entry(value.provinceCode);
    if (prov == null ||
        prov.code.length != 4 ||
        prov.departmentCode != dep.code) {
      return PeruLocationSelection(departmentCode: dep.code);
    }
    final dist = district(value.districtCode);
    return PeruLocationSelection(
      departmentCode: dep.code,
      provinceCode: prov.code,
      districtCode: dist?.provinceCode == prov.code ? dist?.code : null,
    );
  }

  static String searchKey(String text) {
    const accents = 'áéíóúü';
    const plain = 'aeiouu';
    var result = text.toLowerCase().trim();
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], plain[i]);
    }
    return result;
  }

  static int _compare(PeruLocationEntry a, PeruLocationEntry b) {
    final result = searchKey(a.name)
        .replaceAll('ñ', 'n~')
        .compareTo(searchKey(b.name).replaceAll('ñ', 'n~'));
    return result == 0 ? a.code.compareTo(b.code) : result;
  }

  static List<PeruLocationEntry> _sorted(Iterable<PeruLocationEntry> items) =>
      List.unmodifiable(items.toList()..sort(_compare));
}
