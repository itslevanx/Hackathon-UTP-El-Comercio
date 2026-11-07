import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dart:math';

/// UUID v4 válido para PostgreSQL, creado una vez y conservado en los reintentos.
abstract final class EntityId {
  static final Random _random = Random.secure();

  static String forContext(String context) {
    final bytes = sha1
        .convert(utf8.encode('nexo-context-v1:$context'))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _format(bytes);
  }

  static String create() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return _format(bytes);
  }

  static String _format(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
