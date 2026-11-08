import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/maps/address_lookup_service.dart';
import 'package:hackathon_utp_el_comercio/core/maps/carto_basemap.dart';
import 'package:hackathon_utp_el_comercio/core/maps/chosen_map_location.dart';
import 'package:hackathon_utp_el_comercio/core/maps/explore_map_controller.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/maps/explore_map_screen.dart';
import 'package:hackathon_utp_el_comercio/features/maps/location_picker_screen.dart';
import 'package:hackathon_utp_el_comercio/features/maps/neighborhood_map.dart';

Future<AppController> _app() async {
  final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
  final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false)
    ..simulateNetworkOffline = true;
  final c = AppController(
    database: db,
    remoteGateway: remote,
    outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
  );
  await c.initialize();
  return c;
}

Publication _orphan(String uid) => Publication(
  id: 'orphan',
  clientMutationId: 'orphan-mutation',
  ownerUserId: uid,
  authorId: uid,
  authorAlias: 'Prueba',
  kind: PublicationKind.servicio,
  category: 'electricidad',
  title: 'Electricista',
  description: 'Prueba local',
  neighborhood: 'Zona anterior',
  sector: 'Referencia anterior',
  approxLat: null,
  approxLng: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test(
    'Electricista propia sin UBIGEO ni punto aparece sin inventar coordenadas',
    () async {
      final c = await _app();
      addTearDown(c.dispose);
      await c.database.mergeRemotePublications([_orphan(c.currentUser!.id)]);
      final map = ExploreMapController(c);
      addTearDown(map.dispose);
      await map.refresh();
      final result = map.records.singleWhere(
        (r) => r.publication?.id == 'orphan',
      );
      expect(result.point, isNull);
      expect(result.districtUbigeo, isNull);
    },
  );
  test('Ubicar publicación guarda punto aproximado y operación propia; perfil intacto', () async {
    final c = await _app();
    addTearDown(c.dispose);
    final original = c.currentUser!;
    final legacy = _orphan(original.id);
    await c.database.mergeRemotePublications([legacy]);
    const choice = ChosenMapLocation(
      point: LatLng(-12.076123, -77.063456),
      districtUbigeo: '150110',
      address: 'No debe guardarse',
    );
    await c.updatePublicationLocation(legacy, choice);
    final saved = (await c.database.listPublications(activeUserId: original.id))
        .singleWhere((p) => p.id == legacy.id);
    expect(saved.districtUbigeo, '150110');
    expect(saved.approxLat, -12.076);
    expect(saved.serviceLat, isNull);
    expect(saved.serviceAddress, '');
    expect(c.currentUser!.approxLat, original.approxLat);
    final operation = (await c.database.listOutboxForUser(original.id))
        .singleWhere((op) => op.entityType == 'publication_location');
    expect(operation.expectedVersion, 1);
    expect(operation.decodePayload()['service_address'], '');
    expect(saved.syncStatus, SyncStatus.pendiente);
    c.remoteGateway.simulateNetworkOffline = false;
    await c.outboxSyncService.syncPendingForUser(original.id);
    final synced = (await c.database.listPublications(
      activeUserId: original.id,
    )).singleWhere((p) => p.id == legacy.id);
    expect(synced.syncStatus, SyncStatus.confirmado);
    expect(synced.version, 2);
  });
  test(
    'Publicación nueva conserva punto, dirección consentida y cola offline',
    () async {
      final c = await _app();
      addTearDown(c.dispose);
      final created = await c.submitPublication(
        kind: PublicationKind.servicio,
        category: 'electricidad',
        title: 'Servicio local de prueba',
        description: 'Registro de prueba sin envío a Supabase',
        location: const ChosenMapLocation(
          point: LatLng(-12.076123, -77.063456),
          districtUbigeo: '150110',
          shareExactService: true,
          address: 'Lugar de atención de prueba',
        ),
      );
      expect(created.serviceLat, -12.076123);
      expect(created.approxLat, -12.076);
      expect(created.districtUbigeo, '150110');
      expect(created.shareServiceLocation, isTrue);
      final payload = (await c.database.listOutboxForUser(c.currentUser!.id))
          .singleWhere((op) => op.entityId == created.id)
          .decodePayload();
      expect(payload['service_address'], 'Lugar de atención de prueba');
      expect(payload['service_lng'], -77.063456);
      expect(created.syncStatus, SyncStatus.pendiente);
    },
  );
  test('Punto exacto exige consentimiento y se elimina al retirarlo', () async {
    final c = await _app();
    addTearDown(c.dispose);
    final p = _orphan(c.currentUser!.id);
    await c.database.mergeRemotePublications([p]);
    const choice = ChosenMapLocation(
      point: LatLng(-12.076123, -77.063456),
      districtUbigeo: '150110',
      shareExactService: true,
      address: 'Lugar de atención de prueba',
    );
    await c.updatePublicationLocation(p, choice);
    final saved = (await c.database.listPublications(
      activeUserId: c.currentUser!.id,
    )).singleWhere((value) => value.id == p.id);
    expect(NeighborhoodMapRecord.publication(saved).point, choice.point);
    expect(saved.serviceAddress, 'Lugar de atención de prueba');
    final private = saved.copyWith(shareServiceLocation: false);
    expect(private.serviceLat, isNull);
    expect(private.serviceAddress, '');
    expect(
      NeighborhoodMapRecord.publication(private).point,
      const LatLng(-12.076, -77.063),
    );
    final favor = await c.submitPublication(
      kind: PublicationKind.favorSolicitud,
      category: 'general',
      title: 'Prueba',
      description: 'Prueba',
    );
    await expectLater(
      c.updatePublicationLocation(favor, choice),
      throwsStateError,
    );
    await expectLater(
      c.updatePublicationLocation(_orphan('otra-cuenta'), choice),
      throwsStateError,
    );
  });
  test(
    'Confirmar creación conserva la ubicación editada que sigue pendiente',
    () async {
      final c = await _app();
      addTearDown(c.dispose);
      final uid = c.currentUser!.id;
      final created = await c.submitPublication(
        kind: PublicationKind.servicio,
        category: 'electricidad',
        title: 'Prueba',
        description: 'Prueba local',
      );
      await c.updatePublicationLocation(
        created,
        const ChosenMapLocation(
          point: LatLng(-12.076123, -77.063456),
          districtUbigeo: '150110',
        ),
      );
      await c.database.updateOutboxAndEntityStatus(
        operationId: created.clientMutationId,
        newStatus: SyncStatus.confirmado,
        confirmedServerVersion: 1,
      );
      final saved = (await c.database.listPublications(activeUserId: uid))
          .singleWhere((p) => p.id == created.id);
      expect(saved.syncStatus, SyncStatus.pendiente);
      expect(saved.version, 2);
      expect(saved.districtUbigeo, '150110');
      await c.database.mergeRemotePublications([
        created.copyWith(syncStatus: SyncStatus.confirmado),
      ]);
      final preserved = (await c.database.listPublications(activeUserId: uid))
          .singleWhere((p) => p.id == created.id);
      expect(preserved.districtUbigeo, '150110');
    },
  );
  testWidgets(
    'La propia publicación sin ubicación ofrece una acción para ubicarla',
    (tester) async {
      final c = await _app();
      addTearDown(c.dispose);
      await c.database.mergeRemotePublications([_orphan(c.currentUser!.id)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExploreMapScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('map_edit_location_pub:orphan'));
      await tester.scrollUntilVisible(
        edit,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('map_results_scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Ubicar esta publicación en el mapa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Buscar dirección confirma punto sin publicar dirección por defecto',
    (tester) async {
      final catalog = await PeruLocationCatalog.load();
      ChosenMapLocation? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await Navigator.push<ChosenMapLocation>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationPickerScreen(
                        catalog: catalog,
                        districtUbigeo: '150110',
                        lookup: _Lookup(),
                      ),
                    ),
                  );
                },
                child: const Text('Elegir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Elegir'));
      await tester.pumpAndSettle();
      final address = find.byKey(const Key('input_location_address'));
      await tester.ensureVisible(address);
      await tester.enterText(address, 'Referencia pública de prueba');
      final search = find.byKey(const Key('btn_search_location_address'));
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('btn_confirm_location_point'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.districtUbigeo, '150110');
      expect(result?.shareExactService, isFalse);
      expect(result?.address, '');
      expect(result?.publicLat, -12.076);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Pin arrastrable sin pedir GPS', (tester) async {
    LatLng? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NeighborhoodMap(
              records: const [],
              center: const LatLng(-12.076, -77.063),
              selectionPoint: const LatLng(-12.076, -77.063),
              onSelectPoint: (point) => chosen = point,
              onSelect: (_) {},
              configuration: const CartoConfiguration(apiKey: 'test'),
              tileProvider: _Tiles(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byKey(const Key('map_location_picker_pin')),
      const Offset(40, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(chosen, isNotNull);
    expect(chosen!.longitude, isNot(-77.063));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('SQLite v2 migra a v3 y admite ubicación en borradores', () async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    final folder = await Directory.systemTemp.createTemp('nexo-location-v2');
    final path = '${folder.path}/old.db';
    final old = await ffi.databaseFactoryFfi.openDatabase(
      path,
      options: ffi.OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          for (final sql in SqfliteStoreEngine.schemaStatements) {
            final lines = sql
                .split('\n')
                .where(
                  (line) => ![
                    'share_service_location',
                    'service_lat',
                    'service_lng',
                    'service_address',
                    'location_json',
                  ].any(line.contains),
                )
                .join('\n');
            await db.execute(lines);
          }
        },
      ),
    );
    final data = _orphan('legacy-user').toSqlMap()
      ..remove('share_service_location')
      ..remove('service_lat')
      ..remove('service_lng')
      ..remove('service_address');
    await old.insert('publications_local', data);
    await old.close();
    final engine = SqfliteStoreEngine(databaseFileName: path);
    final db = LocalSqliteDatabase(engine: engine);
    await db.initAndSeedDemoData(seedDemo: false);
    await db.saveDraft(
      FormDraft(
        draftKey: 'test',
        ownerUserId: 'legacy-user',
        kind: PublicationKind.servicio,
        title: 'Borrador',
        description: 'Texto',
        locationJson: jsonEncode(
          const ChosenMapLocation(
            point: LatLng(-12.076, -77.063),
            districtUbigeo: '150110',
          ).toMap(),
        ),
        updatedAt: DateTime.utc(2026),
      ),
    );
    expect(
      (await db.listPublications(activeUserId: 'legacy-user')).single.title,
      'Electricista',
    );
    expect(
      (await db.getDraft(
        ownerUserId: 'legacy-user',
        draftKey: 'test',
      ))?.locationJson,
      isNotEmpty,
    );
    await engine.close();
    await folder.delete(recursive: true);
  });
}

class _Lookup extends AddressLookupService {
  @override
  Future<List<LatLng>> search(String address, String area) async => [
    const LatLng(-12.076123, -77.063456),
  ];
}

class _Tiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
}
