import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/config/app_config.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/models/entity_id.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test('El retorno de autenticación rechaza enlaces ajenos', () {
    expect(
      AppConfig.isAuthCallbackUri(
        Uri.parse('${AppConfig.authRedirectUrl}?code=example-code'),
      ),
      isTrue,
    );
    for (final url in [
      'https://auth-callback?code=example-code',
      'pe.vecinos.app://another-host?code=example-code',
      'pe.vecinos.app://auth-callback/another-path?code=example-code',
      'pe.vecinos.app://user@auth-callback?code=example-code',
      'pe.vecinos.app://auth-callback:8080?code=example-code',
    ]) {
      expect(AppConfig.isAuthCallbackUri(Uri.parse(url)), isFalse);
    }
  });

  test('Confirmar el correo retoma la acción pendiente en la app', () async {
    final remote = _AuthLinkGateway();
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    final controller = AppController(
      database: db,
      remoteGateway: remote,
      outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
    );
    await controller.initialize(startWithActiveSession: false);
    controller.openQuickPublish(
      presetKind: PublicationKind.emergenciaSolicitud,
      lockTypeForTwoClickFlow: true,
    );
    expect(controller.currentSection, AppSection.autenticacion);
    final restored = Completer<void>();
    controller.addListener(() {
      if (controller.currentSection == AppSection.publicarRapido &&
          !restored.isCompleted) {
        restored.complete();
      }
    });
    remote.loadSession = () async => _confirmedProfile;
    remote.events.add(null);
    await restored.future.timeout(const Duration(seconds: 2));
    expect(controller.currentUser?.id, _confirmedProfile.id);
    expect(controller.publishPresetKind, PublicationKind.emergenciaSolicitud);
    expect(await db.listOutboxForUser(_confirmedProfile.id), isEmpty);
    controller.dispose();
    await remote.events.close();
  });

  test('Un retorno tardío no restaura una sesión que ya se cerró', () async {
    final remote = _AuthLinkGateway();
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    final controller = AppController(
      database: db,
      remoteGateway: remote,
      outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
    );
    await controller.initialize(startWithActiveSession: false);
    final delayedProfile = Completer<UserProfile?>();
    remote.loadSession = () => delayedProfile.future;
    remote.events.add(null);
    await controller.signOut();
    delayedProfile.complete(_confirmedProfile);
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentUser, isNull);
    expect(controller.currentSection, AppSection.inicio);
    controller.dispose();
    await remote.events.close();
  });
  test('Sin backend no hay login ficticio ni confirmación de envío', () async {
    final remote = SupabaseRemoteGateway();
    expect(
      () => remote.signInAccount(
        email: 'test@example.com',
        password: 'password123',
      ),
      throwsStateError,
    );
    final result = await remote.pushOutboxOperation(
      OutboxOperation(
        operationId: EntityId.create(),
        ownerUserId: EntityId.create(),
        entityType: 'publication',
        entityId: EntityId.create(),
        action: 'upsert',
        payloadJson: '{}',
        syncStatus: SyncStatus.pendiente,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    expect(result.status, SyncStatus.pendiente);
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    final controller = AppController(
      database: db,
      remoteGateway: remote,
      outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
    );
    await controller.initialize();
    expect(controller.currentUser, isNull);
    expect(controller.publications, isEmpty);
    controller.dispose();
  });

  testWidgets(
    'Ofrecer recurso conserva consentimiento desmarcado y termina en tres clics',
    (tester) async {
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false);
      final controller = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: controller,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('btn_home_ofrecer_recurso')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_home_ofrecer_recurso')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('checkbox_resource_consent')),
            )
            .value,
        isFalse,
      );
      await tester.enterText(
        find.byKey(const Key('input_publish_title')),
        'Comparto una linterna',
      );
      await tester.enterText(
        find.byKey(const Key('input_publish_description')),
        'Puedo prestarla en mi zona',
      );
      await tester.ensureVisible(
        find.byKey(const Key('checkbox_resource_consent')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkbox_resource_consent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('btn_submit_publication')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_submit_publication')));
      await tester.pumpAndSettle();
      expect(controller.lastSubmittedPublication?.shareResourceConsent, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  test('Identificadores UUID válidos y estables por contexto', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(pattern.hasMatch(EntityId.create()), isTrue);
    expect(
      EntityId.forContext('conversation:one'),
      EntityId.forContext('conversation:one'),
    );
    expect(
      EntityId.forContext('conversation:one'),
      isNot(EntityId.forContext('conversation:two')),
    );
  });

  test(
    'SQLite real conserva pendientes y borradores después de cerrar y reabrir',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp(
        'nexo-sqlite-test-',
      );
      final path = '${directory.path}/neighborhood.db';
      final engine = SqfliteStoreEngine(databaseFileName: path);
      final db = LocalSqliteDatabase(engine: engine);
      await db.initAndSeedDemoData(seedDemo: false);
      final owner = EntityId.create();
      final publication = Publication(
        id: EntityId.create(),
        clientMutationId: EntityId.create(),
        ownerUserId: owner,
        authorId: owner,
        authorAlias: 'Vecina',
        kind: PublicationKind.emergenciaSolicitud,
        category: 'agua',
        title: 'Necesito agua',
        description: 'Solicitud local',
        neighborhood: 'Pueblo Libre',
        sector: 'San Martín',
        approxLat: -12.076,
        approxLng: -77.063,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.createOrUpdatePublicationTransactional(publication);
      await db.createOrUpdatePublicationTransactional(publication);
      await db.saveDraft(
        FormDraft(
          draftKey: 'chat_one',
          ownerUserId: owner,
          kind: PublicationKind.servicio,
          title: 'Chat',
          description: 'Texto conservado',
          updatedAt: DateTime.now(),
        ),
      );
      await engine.close();
      final reopenedEngine = SqfliteStoreEngine(databaseFileName: path);
      final reopened = LocalSqliteDatabase(engine: reopenedEngine);
      await reopened.initAndSeedDemoData(seedDemo: false);
      expect((await reopened.listPublications(activeUserId: owner)).length, 1);
      expect((await reopened.listOutboxForUser(owner)).length, 1);
      expect(await reopened.listOutboxForUser('otra-cuenta'), isEmpty);
      expect(
        (await reopened.getDraft(
          ownerUserId: owner,
          draftKey: 'chat_one',
        ))?.description,
        'Texto conservado',
      );
      await reopenedEngine.close();
      await directory.delete(recursive: true);
    },
  );

  test('Los pendientes se conservan al descargar y el conflicto guarda una copia recuperable', () async {
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    await db.initAndSeedDemoData(seedDemo: false);
    final owner = EntityId.create();
    final local = Publication(
      id: EntityId.create(),
      clientMutationId: EntityId.create(),
      ownerUserId: owner,
      authorId: owner,
      authorAlias: 'Vecina',
      kind: PublicationKind.favorSolicitud,
      category: 'agua',
      title: 'Texto local',
      description: 'Contenido pendiente',
      neighborhood: 'Pueblo Libre',
      sector: 'San Martín',
      approxLat: -12.076,
      approxLng: -77.063,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.createOrUpdatePublicationTransactional(local);
    final remote = local.copyWith(
      title: 'Versión del barrio',
      version: 4,
      syncStatus: SyncStatus.confirmado,
    );
    await db.mergeRemotePublications([remote]);
    expect(
      (await db.listPublications(activeUserId: owner)).single.title,
      'Texto local',
    );
    expect((await db.listOutboxForUser(owner)).length, 1);
    await db.keepDraftAndAcceptRemote(remote, owner);
    expect(
      (await db.getDraft(
        ownerUserId: owner,
        draftKey: 'conflict_${local.id}',
      ))?.description,
      'Contenido pendiente',
    );
    expect(
      (await db.listPublications(activeUserId: owner)).single.title,
      'Versión del barrio',
    );
    expect(await db.listOutboxForUser(owner), isEmpty);
  });

  testWidgets(
    'Pantalla estrecha y texto 200% no desbordan Inicio y publicación',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false);
      final controller = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await controller.initialize();
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: controller,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.openQuickPublish(
        presetKind: PublicationKind.emergenciaSolicitud,
        lockTypeForTwoClickFlow: true,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final section in [
        AppSection.servicios,
        AppSection.favores,
        AppSection.emergencias,
        AppSection.misActividades,
        AppSection.autenticacion,
        AppSection.practicaSimulacro,
      ]) {
        controller.navigateTo(section);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Desbordamiento en $section',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}

final _confirmedProfile = UserProfile(
  id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  alias: 'Vecino de prueba',
  neighborhood: 'Pueblo Libre',
  sector: 'Sector San Martín',
  updatedAt: DateTime.utc(2026, 11, 7),
);

class _AuthLinkGateway extends SupabaseRemoteGateway {
  _AuthLinkGateway() : super(forceSupabaseAvailable: false);
  final events = StreamController<void>.broadcast(sync: true);
  Future<UserProfile?> Function()? loadSession;

  @override
  Stream<void> get signedInSessionChanges => events.stream;

  @override
  Future<UserProfile?> getCurrentSessionProfile() async => loadSession?.call();
}
