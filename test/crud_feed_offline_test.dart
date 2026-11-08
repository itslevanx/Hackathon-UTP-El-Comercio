import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:hackathon_utp_el_comercio/core/maps/carto_basemap.dart';
import 'package:hackathon_utp_el_comercio/core/maps/carto_tile_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Caché de mapas sobrevive al cierre, caduca y respeta el límite de espacio',
    () async {
      ffi.sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('nexo-map-cache');
      var time = DateTime.utc(2026, 11, 7);
      final dbPath = '${dir.path}/tiles.db';
      var cache = CartoTileCache(
        factory: ffi.databaseFactoryFfi,
        databasePath: dbPath,
        maxBytes: 8,
        now: () => time,
      );
      await cache.write(
        'first',
        Uint8List.fromList([1, 2, 3, 4]),
        const Duration(days: 90),
      );
      await cache.close();
      cache = CartoTileCache(
        factory: ffi.databaseFactoryFfi,
        databasePath: dbPath,
        maxBytes: 8,
        now: () => time,
      );
      expect(await cache.read('first'), [1, 2, 3, 4]);
      time = time.add(const Duration(seconds: 1));
      await cache.write('second', Uint8List(5), const Duration(days: 1));
      expect(await cache.read('first'), isNull);
      expect(await cache.read('second'), isNotNull);
      time = time.add(const Duration(days: 31));
      expect(await cache.read('second'), isNull);
      await cache.close();
      await dir.delete(recursive: true);
      expect(cartoCacheLifetime({'cache-control': 'no-store'}), Duration.zero);
      expect(
        cartoCacheLifetime({'cache-control': 'max-age=3600', 'age': '60'}),
        const Duration(seconds: 3540),
      );
    },
  );
  test('Un tile consultado online reaparece desde SQLite sin realizar HTTP offline', () async {
    ffi.sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('nexo-tile-offline');
    final dbPath = '${dir.path}/tiles.db';
    var cache = CartoTileCache(
      factory: ffi.databaseFactoryFfi,
      databasePath: dbPath,
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    var calls = 0;
    final online = CartoTileProvider(
      configuration: const CartoConfiguration(apiKey: 'prueba-local'),
      identity: {},
      tileCache: cache,
      onTileResult: (_) {},
      client: MockClient((_) async {
        calls++;
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    const tile = TileCoordinates(1, 1, 3);
    expect(await online.bytes(tile, Completer<void>().future), png);
    await online.dispose();
    await cache.close();
    cache = CartoTileCache(
      factory: ffi.databaseFactoryFfi,
      databasePath: dbPath,
    );
    final offline = CartoTileProvider(
      configuration: const CartoConfiguration(apiKey: 'prueba-local'),
      identity: {},
      online: false,
      tileCache: cache,
      onTileResult: (_) {},
      client: MockClient((_) async {
        calls++;
        throw StateError('No debe consultar la red');
      }),
    );
    expect(await offline.bytes(tile, Completer<void>().future), png);
    await offline.bytes(
      const TileCoordinates(2, 1, 3),
      Completer<void>().future,
    );
    expect(calls, 1);
    await offline.dispose();
    await cache.close();
    await dir.delete(recursive: true);
  });
}
