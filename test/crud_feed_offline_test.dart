import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/maps/carto_basemap.dart';
import 'package:hackathon_utp_el_comercio/core/maps/carto_tile_cache.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/publish/publication_owner_actions.dart';

Future<AppController> app({SupabaseRemoteGateway? gateway}) async {
  final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
  final remote =
      gateway ??
      (SupabaseRemoteGateway(forceSupabaseAvailable: false)
        ..simulateNetworkOffline = true);
  final c = AppController(
    database: db,
    remoteGateway: remote,
    outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
  );
  await c.initialize();
  return c;
}

Future<Publication> create(AppController c, PublicationKind kind) =>
    c.submitPublication(
      kind: kind,
      category: 'general',
      title: 'Aviso ${kind.dbValue}',
      description: 'Descripción de prueba',
      shareResourceConsent: kind == PublicationKind.emergenciaOferta,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Todos los tipos permiten crear, editar y eliminar sin conexión; la cola se confirma en orden', () async {
    final c = await app();
    addTearDown(c.dispose);
    for (final kind in PublicationKind.values) {
      final original = await create(c, kind);
      await c.editPublication(
        original,
        title: 'Título corregido',
        description: 'Nueva descripción',
        category: 'general',
      );
      final edited = c.publications.singleWhere((p) => p.id == original.id);
      expect(edited.title, 'Título corregido');
      expect(edited.version, 2);
      await c.deletePublication(edited);
      expect(c.publications.where((p) => p.id == original.id), isEmpty);
      final ops = (await c.database.listOutboxForUser(c.currentUser!.id))
          .where((o) => o.entityId == original.id)
          .toList();
      expect(ops.map((o) => o.entityType), [
        'publication',
        'publication_edit',
        'publication_delete',
      ]);
      expect(ops.map((o) => o.expectedVersion), [1, 1, 2]);
    }
    c.remoteGateway.simulateNetworkOffline = false;
    await c.outboxSyncService.syncPendingForUser(c.currentUser!.id);
    expect(await c.database.listOutboxForUser(c.currentUser!.id), isEmpty);
    await c.refreshAllLocalData();
    expect(
      c.publications.where(
        (p) => p.authorId == c.currentUser!.id && p.title == 'Título corregido',
      ),
      isEmpty,
    );
  });
  test('Eliminar una creación nunca enviada cancela su cola sin publicarla al reconectar', () async {
    final c = await app();
    addTearDown(c.dispose);
    c.outboxSyncService.networkAvailable = false;
    final p = await create(c, PublicationKind.emergenciaSolicitud);
    await c.editPublication(
      p,
      title: 'Texto corregido',
      description: 'Borrador de prueba',
      category: 'general',
    );
    await c.deletePublication(c.publications.singleWhere((v) => v.id == p.id));
    expect(
      (await c.database.listOutboxForUser(c.currentUser!.id))
          .where((op) => op.entityId == p.id),
      isEmpty,
    );
    c.outboxSyncService.networkAvailable = true;
    c.remoteGateway.simulateNetworkOffline = false;
    final result = await c.outboxSyncService.syncPendingForUser(
      c.currentUser!.id,
    );
    expect(result.confirmedCount, 0);
    expect(c.publications.any((v) => v.id == p.id), isFalse);
  });
  test('Otra cuenta no puede editar ni eliminar; una eliminación remota no se resucita con una respuesta antigua', () async {
    final c = await app();
    addTearDown(c.dispose);
    final other = c.publications.firstWhere(
      (p) => p.authorId != c.currentUser!.id,
    );
    await expectLater(
      c.editPublication(
        other,
        title: 'No permitido',
        description: 'Prueba',
        category: 'general',
      ),
      throwsStateError,
    );
    await expectLater(c.deletePublication(other), throwsStateError);
    await c.database.applyPublicationTombstones([
      {
        'publication_id': other.id,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
    await c.database.mergeRemotePublications([other]);
    await c.refreshAllLocalData();
    expect(c.publications.where((p) => p.id == other.id), isEmpty);
  });
  test(
    'Un conflicto bloquea los cambios posteriores del mismo aviso',
    () async {
      final gateway = _BlockedGateway()..simulateNetworkOffline = true;
      final c = await app(gateway: gateway);
      addTearDown(c.dispose);
      final p = await create(c, PublicationKind.anuncio);
      await c.editPublication(
        p,
        title: 'Edición guardada',
        description: 'Texto',
        category: 'general',
      );
      gateway.simulateNetworkOffline = false;
      gateway.calls.clear();
      await c.outboxSyncService.syncPendingForUser(c.currentUser!.id);
      expect(gateway.calls, ['publication']);
      expect((await c.database.listOutboxForUser(c.currentUser!.id)).length, 2);
    },
  );
  test('SQLite 3 migra a 4 sin perder avisos y conserva la eliminación pendiente al reabrir', () async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('nexo-crud-v3');
    final file = '${dir.path}/old.db';
    final old = await ffi.databaseFactoryFfi.openDatabase(
      file,
      options: ffi.OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          for (final sql in SqfliteStoreEngine.schemaStatements) {
            await db.execute(sql.replaceAll('      deleted_at TEXT,', ''));
          }
        },
      ),
    );
    final p = Publication(
      id: 'legacy-crud',
      clientMutationId: 'legacy-op',
      ownerUserId: 'owner',
      authorId: 'owner',
      authorAlias: 'Vecino',
      kind: PublicationKind.anuncio,
      category: 'general',
      title: 'Aviso anterior',
      description: 'Conservar',
      neighborhood: 'Pueblo Libre',
      sector: 'Zona',
      approxLat: -12.076,
      approxLng: -77.063,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await old.insert(
      'publications_local',
      Map.of(p.toSqlMap())..remove('deleted_at'),
    );
    await old.close();
    var engine = SqfliteStoreEngine(databaseFileName: file);
    var db = LocalSqliteDatabase(engine: engine);
    await db.initAndSeedDemoData(seedDemo: false);
    expect(
      (await db.listPublications(activeUserId: 'owner')).single.title,
      'Aviso anterior',
    );
    await db.editPublication(
      publicationId: p.id,
      actingUserId: 'owner',
      changes: {},
      delete: true,
    );
    await engine.close();
    engine = SqfliteStoreEngine(databaseFileName: file);
    db = LocalSqliteDatabase(engine: engine);
    await db.initAndSeedDemoData(seedDemo: false);
    expect(await db.listPublications(activeUserId: 'owner'), isEmpty);
    expect(
      (await db.listOutboxForUser('owner')).single.entityType,
      'publication_delete',
    );
    await engine.close();
    await dir.delete(recursive: true);
  });
  testWidgets('Eliminar pide confirmación; cancelar conserva el aviso', (
    tester,
  ) async {
    final c = await app();
    addTearDown(c.dispose);
    final p = await create(c, PublicationKind.prestamo);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicationOwnerActions(controller: c, publication: p),
        ),
      ),
    );
    await tester.tap(find.byKey(ValueKey('delete_publication_${p.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conservar'));
    await tester.pumpAndSettle();
    expect(c.publications.any((v) => v.id == p.id), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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

class _BlockedGateway extends SupabaseRemoteGateway {
  _BlockedGateway() : super(forceSupabaseAvailable: false);
  final calls = <String>[];
  @override
  Future<RemoteSyncResult> pushOutboxOperation(OutboxOperation op) async {
    if (simulateNetworkOffline) {
      return const RemoteSyncResult(status: SyncStatus.pendiente);
    }
    calls.add(op.entityType);
    return const RemoteSyncResult(status: SyncStatus.conflicto);
  }
}
