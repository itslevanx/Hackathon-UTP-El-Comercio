import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

abstract class MapTileCache {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes, Duration lifetime);
}

/// Solo conserva tiles solicitados al recorrer el mapa; no precarga regiones.
class CartoTileCache implements MapTileCache {
  CartoTileCache({
    this.factory,
    this.databasePath,
    this.maxBytes = 100 * 1024 * 1024,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  static final shared = CartoTileCache();
  final DatabaseFactory? factory;
  final String? databasePath;
  final int maxBytes;
  final DateTime Function() now;
  Future<Database>? _opening;
  Future<Database> _open() async {
    try {
      return await (_opening ??= _create());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _create() async {
    final db = await (factory ?? databaseFactory).openDatabase(
      databasePath ??
          path.join(await getDatabasesPath(), 'nexo_carto_cache_v1.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE tiles (tile_key TEXT PRIMARY KEY, bytes BLOB NOT NULL, expires INTEGER NOT NULL, accessed INTEGER NOT NULL, size INTEGER NOT NULL)',
          );
          await db.execute('CREATE INDEX tiles_expiry ON tiles(expires)');
          await db.execute('CREATE INDEX tiles_access ON tiles(accessed)');
        },
      ),
    );
    await db.delete(
      'tiles',
      where: 'expires <= ?',
      whereArgs: [now().millisecondsSinceEpoch],
    );
    return db;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final db = await _open();
    final time = now().millisecondsSinceEpoch;
    final rows = await db.query(
      'tiles',
      columns: ['bytes', 'expires'],
      where: 'tile_key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    if ((rows.single['expires'] as int) <= time) {
      await db.delete('tiles', where: 'tile_key = ?', whereArgs: [key]);
      return null;
    }
    await db.update(
      'tiles',
      {'accessed': time},
      where: 'tile_key = ?',
      whereArgs: [key],
    );
    return Uint8List.fromList(rows.single['bytes'] as List<int>);
  }

  @override
  Future<void> write(String key, Uint8List bytes, Duration lifetime) async {
    if (lifetime <= Duration.zero || bytes.length > maxBytes) return;
    final db = await _open();
    final time = now().millisecondsSinceEpoch;
    final ttl = lifetime > const Duration(days: 30)
        ? const Duration(days: 30)
        : lifetime;
    await db.transaction((txn) async {
      await txn.delete('tiles', where: 'expires <= ?', whereArgs: [time]);
      await txn.insert('tiles', {
        'tile_key': key,
        'bytes': bytes,
        'expires': time + ttl.inMilliseconds,
        'accessed': time,
        'size': bytes.length,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      var size =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT SUM(size) FROM tiles'),
          ) ??
          0;
      if (size <= maxBytes) return;
      final oldest = await txn.query(
        'tiles',
        columns: ['tile_key', 'size'],
        orderBy: 'accessed ASC, tile_key ASC',
      );
      for (final row in oldest) {
        if (size <= maxBytes) break;
        await txn.delete(
          'tiles',
          where: 'tile_key = ?',
          whereArgs: [row['tile_key']],
        );
        size -= row['size'] as int;
      }
    });
  }

  Future<void> clear() async {
    await (await _open()).delete('tiles');
  }

  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
    _opening = null;
  }
}

Duration cartoCacheLifetime(Map<String, String> headers) {
  final control = headers['cache-control']?.toLowerCase() ?? '';
  if (control.contains('no-store') || control.contains('no-cache')) {
    return Duration.zero;
  }
  final match = RegExp(r'(?:^|,)\s*max-age=(\d+)').firstMatch(control);
  final seconds = match == null
      ? const Duration(days: 30).inSeconds
      : int.parse(match[1]!);
  final age = int.tryParse(headers['age'] ?? '0') ?? 0;
  final remaining = (seconds - age).clamp(
    0,
    const Duration(days: 30).inSeconds,
  );
  return Duration(seconds: remaining);
}
