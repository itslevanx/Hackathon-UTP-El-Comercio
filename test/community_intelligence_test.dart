import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/intelligence/community_intelligence.dart';
import 'package:hackathon_utp_el_comercio/core/intelligence/intelligence_controller.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/features/intelligence/recommendations_screen.dart';

Map<String, dynamic> need() => {
  'id': 'need',
  'author_id': 'me',
  'kind': 'favor_solicitud',
  'title': 'Necesito agua potable',
  'author_alias': 'Lucía Rojas',
  'status': 'abierta',
  'category': 'agua',
  'district_ubigeo': '150110',
  'approx_lat': -12.076,
  'approx_lng': -77.063,
  'priority': 'normal',
};
Map<String, dynamic> offer(String id, {String category = 'agua'}) => {
  ...need(),
  'id': id,
  'author_id': 'other',
  'kind': 'donacion',
  'category': category,
  'title': 'Agua disponible',
  'description': 'Agua para vecinos',
  'author_alias': 'Vecina',
};

class SnapshotGateway extends SupabaseRemoteGateway {
  SnapshotGateway() : super(forceSupabaseAvailable: false);
  bool online = false;
  int calls = 0;
  bool denied = false;
  bool networkFailure = false;
  Completer<Map<String, dynamic>>? pending;
  bool paged = false;
  String? cursor;
  @override
  bool get isLiveSupabaseConnected => online;
  @override
  Future<Map<String, dynamic>> fetchCommunityIntelligence({
    required String district,
    required double radius,
    required int windowMinutes,
    required int minimumNeighbors,
    String? requestId,
    String? afterId,
  }) async {
    calls++;
    cursor = afterId;
    if (pending != null) return pending!.future;
    if (networkFailure) throw TimeoutException('offline');
    if (denied) {
      throw const PostgrestException(message: 'Sin acceso', code: '42501');
    }
    return {
      'fetched_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'complete': !(paged && afterId == null),
      if (paged && afterId == null) 'next_cursor': 'a',
      'clusters': [],
      if (requestId != null) 'request': need(),
      if (requestId != null) 'offers': [offer(afterId == null ? 'a' : 'b')],
    };
  }
}

Future<AppController> app(SnapshotGateway gateway) async {
  final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
  final c = AppController(
    database: db,
    remoteGateway: gateway,
    outboxSyncService: OutboxSyncService(database: db, remoteGateway: gateway),
  );
  await c.initialize();
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => PeruLocationCatalog.load());
  test(
    'Sin ofertas explica el recurso pendiente y distingue errores de conexión',
    () async {
      final gateway = SnapshotGateway();
      final c = await app(gateway);
      addTearDown(c.dispose);
      final data = IntelligenceController(c, requestId: 'need');
      addTearDown(data.dispose);
      data.snapshot = {
        'request': need(),
        'offers': [],
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      };
      data.saved = false;
      expect(data.matches, isEmpty);
      expect(data.emptyMatchesMessage, contains('ofertas compatibles de Agua'));
      expect(data.emptyMatchesMessage, contains('otros vecinos'));
      data.saved = true;
      expect(data.emptyMatchesMessage, contains('guardadas'));
      data.snapshot = null;
      data.notice = 'No se pudo actualizar.';
      expect(data.emptyMatchesMessage, data.notice);
    },
  );
  test('Diez ofertas de agua aparecen puntuadas; transporte y agotadas quedan fuera', () {
    final offers = List.generate(
      10,
      (i) => {...offer('water-$i'), 'approx_lat': null, 'approx_lng': null},
    );
    final results = CommunityMatcher().rank(need(), [
      ...offers,
      offer('transport', category: 'transporte'),
      {...offer('empty'), 'status': 'resuelta'},
    ]);
    expect(results, hasLength(10));
    expect(
      results.every((r) => r.score == 50 && r.distanceMeters == null),
      isTrue,
    );
    expect(results.map((r) => r.id).toSet(), hasLength(10));
  });
  test('Compatibilidad exacta y aliases explícitos, sin urgencia que venza incompatibilidad', () {
    final request = {...need(), 'priority': 'emergencia'};
    final results = CommunityMatcher().rank(request, [
      offer('water'),
      offer('transport', category: 'transporte'),
      offer('alias', category: 'agua_potable'),
    ]);
    expect(results.map((e) => e.id), ['alias', 'water']);
    expect(
      CommunityMatcher().rank(
        {...request, 'category': 'general'},
        [offer('g', category: 'general')],
      ),
      isEmpty,
    );
  });
  test('Filtros de agotado, eliminado, reservado, propio y consentimiento antes de puntuar', () {
    final offers = [
      {...offer('resolved'), 'status': 'resuelta'},
      {...offer('reserved'), 'status': 'en_coordinacion'},
      {...offer('deleted'), 'deleted_at': '2026-11-08'},
      {...offer('own'), 'author_id': 'me'},
      {
        ...offer('no-consent'),
        'kind': 'emergencia_oferta',
        'share_resource_consent': false,
      },
      {...offer('demo'), 'is_demo': true},
      offer('ok'),
    ];
    expect(CommunityMatcher().rank(need(), offers).map((e) => e.id), ['ok']);
  });
  test('Puntuación configurable, distancia redondeada y empates estables', () {
    final values = CommunityMatcher().rank(need(), [
      offer('b'),
      offer('a'),
      offer('a'),
    ]);
    expect(values.map((e) => e.id), ['a', 'b']);
    expect(values.first.distanceMeters, 50);
    expect(values.first.score, closeTo(74.9375, .0001));
    final adjusted = CommunityMatcher(
      const IntelligenceConfig(
        compatibilityWeight: 1,
        distanceWeight: 0,
        availabilityWeight: 0,
        urgencyWeight: 0,
      ),
    );
    expect(adjusted.rank(need(), [offer('a')]).single.score, 100);
    expect(
      () => CommunityMatcher(const IntelligenceConfig(compatibilityWeight: 2)),
      throwsArgumentError,
    );
  });
  test(
    'Sin coordenadas, distancia desconocida; no inventa cercanía o distrito',
    () {
      final result = CommunityMatcher().rank(need(), [
        {...offer('missing'), 'approx_lat': null},
      ]);
      expect(result.single.distanceMeters, isNull);
      expect(result.single.score, 50);
      expect(
        CommunityMatcher().rank(need(), [
          {...offer('bad'), 'approx_lat': null, 'district_ubigeo': '150101'},
        ]),
        isEmpty,
      );
      expect(
        CommunityMatcher().rank(need(), [
          {...offer('far'), 'approx_lat': -13.1},
        ]),
        isEmpty,
      );
      expect(
        CommunityMatcher().rank(
          {...need(), 'status': 'cancelada'},
          [offer('a')],
        ),
        isEmpty,
      );
    },
  );
  test(
    'Caché separada por cuenta y parámetros; persiste sin alterar la cola',
    () async {
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      await db.initAndSeedDemoData(seedDemo: false);
      await db.saveIntelligenceCache('userA:150110', {
        'clusters': [],
        'complete': true,
      });
      expect(await db.readIntelligenceCache('userB:150110'), isNull);
      expect(
        (await db.readIntelligenceCache('userA:150110'))!['complete'],
        true,
      );
      expect(await db.listOutboxForUser('userA'), isEmpty);
    },
  );
  test('Offline no calcula ni consulta; reconecta, guarda y revoca snapshot al denegar acceso', () async {
    final gateway = SnapshotGateway();
    final c = await app(gateway);
    addTearDown(c.dispose);
    final data = IntelligenceController(c, requestId: 'need');
    addTearDown(data.dispose);
    data.districtOverride = '150110';
    await data.refresh();
    expect(gateway.calls, 0);
    expect(data.matches, isEmpty);
    gateway.online = true;
    await data.refresh();
    expect(data.matches.length, 1);
    expect(data.stale, false);
    gateway.simulateNetworkOffline = true;
    await data.refresh();
    expect(gateway.calls, 1);
    expect(data.stale, true);
    expect(data.matches.length, 1);
    final restored = IntelligenceController(c, requestId: 'need');
    restored.districtOverride = '150110';
    addTearDown(restored.dispose);
    await restored.refresh();
    expect(restored.matches.length, 1);
    expect(gateway.calls, 1);
    gateway.simulateNetworkOffline = false;
    gateway.denied = true;
    await restored.refresh();
    expect(restored.matches, isEmpty);
  });
  testWidgets(
    'Recomendaciones guardadas accesibles, detalle local y contacto deshabilitado offline',
    (tester) async {
      final gateway = SnapshotGateway();
      final c = await app(gateway);
      addTearDown(c.dispose);
      final data = IntelligenceController(c, requestId: 'need');
      data.districtOverride = '150110';
      gateway.online = true;
      await data.refresh();
      gateway.simulateNetworkOffline = true;
      // Screen uses active district; the account has no UBIGEO in legacy fixtures.
      await c.updateLocationPreference(
        neighborhood: 'Comas',
        sector: 'Zona general',
        districtUbigeo: '150110',
        useGpsApprox: false,
        approxLat: null,
        approxLng: null,
      );
      final scoped = IntelligenceController(c, requestId: 'need');
      scoped.districtOverride = '150110';
      gateway.simulateNetworkOffline = false;
      await scoped.refresh();
      gateway.simulateNetworkOffline = true;
      data.dispose();
      scoped.dispose();
      await tester.pumpWidget(
        MaterialApp(
          home: RecommendationsScreen(app: c, requestId: 'need'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agua disponible'), findsOneWidget);
      expect(find.text('Match'), findsOneWidget);
      expect(find.text('Necesito agua potable'), findsOneWidget);
      expect(find.text('SOLICITA · Lucía Rojas'), findsOneWidget);
      final contact = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Contactar'),
      );
      expect(contact.onPressed, isNull);
      await tester.ensureVisible(find.text('Ver detalle'));
      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copia guardada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Pérdida de red conserva la copia y salir elimina la caché sin tocar envíos', () async {
    final gateway = SnapshotGateway();
    final c = await app(gateway);
    addTearDown(c.dispose);
    final data = IntelligenceController(c, requestId: 'need');
    data.districtOverride = '150110';
    addTearDown(data.dispose);
    gateway.online = true;
    await data.refresh();
    expect(data.matches.length, 1);
    gateway.networkFailure = true;
    await data.refresh();
    expect(data.matches.length, 1);
    expect(data.stale, true);
    final owner = c.currentUser!.id;
    await c.database.clearPrivateCacheOnSignOut(owner);
    expect(
      await c.database.readIntelligenceCache('intelligence:v1:${data.scope}'),
      isNull,
    );
  });
  test(
    'Paginación conserva ofertas, evita duplicados y usa cursor estable',
    () async {
      final gateway = SnapshotGateway()..paged = true;
      final c = await app(gateway);
      addTearDown(c.dispose);
      final data = IntelligenceController(c, requestId: 'need');
      data.districtOverride = '150110';
      addTearDown(data.dispose);
      gateway.online = true;
      await data.refresh();
      final timestamp = data.fetchedAt;
      expect(data.matches.map((m) => m.id), ['a']);
      await data.refresh(more: true);
      expect(gateway.cursor, 'a');
      expect(data.matches.map((m) => m.id), ['a', 'b']);
      expect(data.fetchedAt, timestamp);
    },
  );
  test('Respuesta tardía y filtro administrativo incompleto no contaminan otra zona', () async {
    final gateway = SnapshotGateway();
    final c = await app(gateway);
    addTearDown(c.dispose);
    final data = IntelligenceController(c);
    data.districtOverride = '150110';
    addTearDown(data.dispose);
    gateway.online = true;
    gateway.pending = Completer<Map<String, dynamic>>();
    final future = data.refresh();
    await Future<void>.delayed(Duration.zero);
    data.setDistrict(null, complete: false);
    gateway.pending!.complete({
      'clusters': [],
      'fetched_at': DateTime.now().toIso8601String(),
    });
    await future;
    expect(data.snapshot, isNull);
    expect(data.loading, false);
  });
  test('SQLite 5 migra a 6 conservando operaciones existentes', () async {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp(
      'conecta2-intelligence-v5',
    );
    final file = '${dir.path}/legacy.db';
    final legacy = await ffi.databaseFactoryFfi.openDatabase(
      file,
      options: ffi.OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          for (final sql in SqfliteStoreEngine.schemaStatements) {
            if (sql != SqfliteStoreEngine.intelligenceSchema) {
              await db.execute(sql);
            }
          }
        },
      ),
    );
    await legacy.insert('cache_metadata', {
      'cache_key': 'preserve-existing',
      'last_synced_at': '2026-11-08T00:00:00Z',
    });
    await legacy.close();
    final engine = SqfliteStoreEngine(databaseFileName: file);
    await engine.init();
    expect(
      (await engine.query('cache_metadata')).single['cache_key'],
      'preserve-existing',
    );
    await engine.runInTransaction(
      (txn) => txn.upsert('intelligence_cache', 'cache_key', {
        'cache_key': 'snapshot',
        'payload': '{}',
      }),
    );
    expect((await engine.query('intelligence_cache')).length, 1);
    await engine.close();
    await dir.delete(recursive: true);
  });
}
