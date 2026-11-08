import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/features/chat/emergency_group_chat_screen.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';

import 'conecta2_navigation_test.dart' as fixture;

Future<Publication> emergency(AppController c) async {
  final p = Publication.fromSqlMap({
    ...c.publications.first.toSqlMap(),
    'id': 'test-emergency',
    'client_mutation_id': 'test-emergency-op',
    'kind': 'emergencia_solicitud',
    'owner_user_id': c.currentUser!.id,
    'author_id': c.currentUser!.id,
    'status': 'abierta',
    'is_demo': 0,
    'sync_status': 'confirmado',
  });
  await c.database.mergeRemotePublications([p]);
  await c.refreshAllLocalData();
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test('El grupo guarda pendientes por cuenta y permanece en Chats', () async {
    final c = await fixture.app();
    addTearDown(c.dispose);
    final p = await emergency(c);
    await c.openEmergencyGroup(p);
    await c.sendEmergencyGroupMessage(p, 'Coordino la ayuda');
    final history = await c.emergencyGroupHistory(p);
    expect(history.single.body, 'Coordino la ayuda');
    expect(history.single.syncStatus.isConfirmed, isFalse);
    expect(
      await c.database.listEmergencyGroupMessages('otra-cuenta', p.id),
      isEmpty,
    );
    expect(
      (await c.database.listOutboxForUser(c.currentUser!.id))
          .where((o) => o.entityType == 'emergency_group_message'),
      hasLength(1),
    );
    await c.refreshAllLocalData();
    expect(c.emergencyGroupChats.map((p) => p.id), contains(p.id));
    expect(
      c.canViewEmergencyGroup(
        c.publications.firstWhere((p) => p.kind.isService),
      ),
      isFalse,
    );
  });
  test('El grupo rechaza otros distritos y emergencias cerradas', () async {
    final c = await fixture.app();
    addTearDown(c.dispose);
    final own = await emergency(c);
    await c.updateLocationPreference(
      neighborhood: 'Pueblo Libre',
      sector: '',
      approxLat: null,
      approxLng: null,
      useGpsApprox: false,
      districtUbigeo: '150121',
    );
    final neighbor = Publication.fromSqlMap({
      ...own.toSqlMap(),
      'id': 'neighbor-group',
      'client_mutation_id': 'neighbor-op',
      'author_id': 'neighbor',
      'owner_user_id': 'neighbor',
      'district_ubigeo': '150121',
    });
    final outsider = Publication.fromSqlMap({
      ...neighbor.toSqlMap(),
      'id': 'outside-group',
      'client_mutation_id': 'outside-op',
      'district_ubigeo': '150101',
    });
    await c.database.mergeRemotePublications([neighbor, outsider]);
    await c.refreshAllLocalData();
    expect(c.canViewEmergencyGroup(neighbor), isTrue);
    expect(c.canViewEmergencyGroup(outsider), isFalse);
    await expectLater(c.openEmergencyGroup(outsider), throwsStateError);
    await c.database.mergeRemotePublications([
      neighbor.copyWith(
        status: PublicationStatus.resuelta,
        version: neighbor.version + 1,
      ),
    ]);
    await c.refreshAllLocalData();
    await expectLater(
      c.sendEmergencyGroupMessage(neighbor, 'Texto'),
      throwsStateError,
    );
  });
  test(
    'SQLite migra desde v4 y conserva mensajes, visitas y cola al reabrir',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('conecta2-group-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/test.db';
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            for (final sql in SqfliteStoreEngine.schemaStatements) {
              if (!sql.contains('emergency_group_messages_local')) {
                await db.execute(sql);
              }
            }
          },
        ),
      );
      await old.close();
      final engine = SqfliteStoreEngine(databaseFileName: path);
      final db = LocalSqliteDatabase(engine: engine);
      await db.initAndSeedDemoData(seedDemo: false);
      await db.markEmergencyGroupVisited('owner', 'emergency');
      await db.saveDraft(
        FormDraft(
          draftKey: 'group_emergency',
          ownerUserId: 'owner',
          kind: PublicationKind.emergenciaSolicitud,
          title: 'Ayuda',
          description: 'Texto',
          updatedAt: DateTime.now(),
        ),
      );
      final m = await db.saveEmergencyGroupMessage(
        owner: 'owner',
        publicationId: 'emergency',
        senderAlias: 'Vecino',
        body: ' Texto ',
      );
      expect(
        await db.getDraft(ownerUserId: 'owner', draftKey: 'group_emergency'),
        isNull,
      );
      await engine.close();
      final secondEngine = SqfliteStoreEngine(databaseFileName: path);
      addTearDown(secondEngine.close);
      final reopened = LocalSqliteDatabase(engine: secondEngine);
      await reopened.initAndSeedDemoData(seedDemo: false);
      expect(
        (await reopened.listEmergencyGroupMessages(
          'owner',
          'emergency',
        )).single.id,
        m.id,
      );
      expect(
        (await reopened.listOutboxForUser('owner')).single.entityType,
        'emergency_group_message',
      );
      expect(
        await reopened.visitedEmergencyGroups('owner'),
        contains('emergency'),
      );
      expect(
        await reopened.listEmergencyGroupMessages('other', 'emergency'),
        isEmpty,
      );
      await expectLater(
        reopened.saveEmergencyGroupMessage(
          owner: 'owner',
          publicationId: 'emergency',
          senderAlias: 'Vecino',
          body: ' ',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'Cancelar una emergencia nunca enviada conserva el texto y retira su cola',
    () async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      final p = await emergency(c);
      final created = await c.database.createOrUpdatePublicationTransactional(
        p,
      );
      final m = await c.database.saveEmergencyGroupMessage(
        owner: c.currentUser!.id,
        publicationId: created.id,
        senderAlias: 'Vecino',
        body: 'Texto que debe conservarse',
      );
      await c.database.editPublication(
        publicationId: created.id,
        actingUserId: c.currentUser!.id,
        changes: {},
        delete: true,
      );
      expect(await c.database.listOutboxForUser(c.currentUser!.id), isEmpty);
      expect(
        await c.database.listEmergencyGroupMessages(
          c.currentUser!.id,
          created.id,
        ),
        isEmpty,
      );
      expect(
        (await c.database.getDraft(
          ownerUserId: c.currentUser!.id,
          draftKey: 'cancelled_group_${m.id}',
        ))?.description,
        'Texto que debe conservarse',
      );
    },
  );
  test(
    'Confirmar un mensaje retira la operación y mantiene una sola copia local',
    () async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      final p = await emergency(c);
      final m = await c.database.saveEmergencyGroupMessage(
        owner: c.currentUser!.id,
        publicationId: p.id,
        senderAlias: 'Vecino',
        body: 'Ayuda coordinada',
      );
      await c.database.updateOutboxAndEntityStatus(
        operationId: m.clientMutationId,
        newStatus: SyncStatus.confirmado,
      );
      final rows = await c.database.listEmergencyGroupMessages(
        c.currentUser!.id,
        p.id,
      );
      expect(rows.single.syncStatus, SyncStatus.confirmado);
      await c.database.mergeEmergencyGroupMessages(c.currentUser!.id, rows);
      expect(
        await c.database.listEmergencyGroupMessages(c.currentUser!.id, p.id),
        hasLength(1),
      );
      expect(await c.database.listOutboxForUser(c.currentUser!.id), isEmpty);
    },
  );
  testWidgets('El grupo permite escribir sin conexión con texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await fixture.app();
    addTearDown(c.dispose);
    final p = await emergency(c);
    await c.openEmergencyGroup(p);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(body: EmergencyGroupChatScreen(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('input_emergency_group_message')),
      'Llevo agua',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send_emergency_group_message')));
    await tester.pumpAndSettle();
    expect((await c.emergencyGroupHistory(p)).single.body, 'Llevo agua');
    expect(find.text('Llevo agua'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
