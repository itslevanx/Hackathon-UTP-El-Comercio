import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/models/entity_id.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/shared/peru_location_selector.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

Future<void> choose(
  WidgetTester tester,
  String level,
  String query,
  String code,
) async {
  final field = find.byKey(ValueKey('peru_location_$level'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('input_location_search')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('ubigeo_option_$code')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PeruLocationCatalog catalog;
  setUpAll(() async => catalog = await PeruLocationCatalog.load());

  test('Catálogo INEI 2026 íntegro, con ceros, tildes y jerarquías', () {
    expect(catalog.departments.length, 25);
    final provinces = catalog.departments
        .expand((dep) => catalog.provinces(dep.code))
        .toList();
    final districts = provinces
        .expand((prov) => catalog.districts(prov.code))
        .toList();
    expect(provinces.length, 196);
    expect(districts.length, 1893);
    expect(districts.map((entry) => entry.code).toSet().length, 1893);
    expect(catalog.entry('02')?.name, 'Áncash');
    expect(catalog.district('010101')?.name, 'Chachapoyas');
    expect(catalog.district('120307')?.name, 'Sangani');
    expect(catalog.district('160405')?.name, 'Santa Rosa de Loreto');
    expect(
      districts.where((entry) => entry.name == 'Pueblo Libre').length,
      greaterThan(1),
    );
    for (final prov in provinces) {
      expect(catalog.entry(prov.departmentCode), isNotNull);
      final names = catalog
          .districts(prov.code)
          .map(
            (entry) =>
                PeruLocationCatalog.searchKey(entry.name).replaceAll('ñ', 'n~'),
          )
          .toList();
      expect(names, orderedEquals([...names]..sort()));
    }
    expect(catalog.selectionForDistrict('150121').provinceCode, '1501');
    expect(
      catalog.selectionForDistrict('15'),
      const PeruLocationSelection.empty(),
    );
    expect(
      catalog.selectionForDistrict('999999'),
      const PeruLocationSelection.empty(),
    );
    expect(
      catalog.selectionForDistrict('Pueblo Libre'),
      const PeruLocationSelection.empty(),
    );
  });

  test('El catálogo se carga desde recursos sin usar HTTP', () async {
    var requests = 0;
    final loaded = await HttpOverrides.runZoned(
      () async {
        final source = await rootBundle.loadString(
          'assets/geography/peru_ubigeo_2026.json',
        );
        return PeruLocationCatalog.fromJson(source);
      },
      createHttpClient: (_) {
        requests++;
        throw StateError('No hay conexión en esta prueba');
      },
    );
    expect(requests, 0);
    expect(loaded.district('150121')?.name, 'Pueblo Libre');
    expect(loaded.metadata['version'], '2026');
  });

  testWidgets(
    'Selección dependiente, búsqueda sin tildes y validación obligatoria',
    (tester) async {
      final form = GlobalKey<FormState>();
      final selector = GlobalKey<FormFieldState<PeruLocationSelection>>();
      var selection = const PeruLocationSelection.empty();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: PeruLocationSelector(
                    key: selector,
                    catalog: catalog,
                    value: selection,
                    isRequired: true,
                    onChanged: (value) => setState(() => selection = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('peru_location_province')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('peru_location_district')),
            )
            .onPressed,
        isNull,
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(
        find.text('Selecciona departamento, provincia y distrito.'),
        findsOneWidget,
      );
      await choose(tester, 'department', 'lima', '15');
      expect(selection.provinceCode, isNull);
      expect(selection.districtCode, isNull);
      await choose(tester, 'province', 'lima', '1501');
      await choose(tester, 'district', 'pueblo libre', '150121');
      expect(form.currentState!.validate(), isTrue);
      expect(selector.currentState!.value?.districtCode, '150121');
      await choose(tester, 'province', 'barranca', '1502');
      expect(selection.districtCode, isNull);
      await choose(tester, 'district', 'barranca', '150201');
      await choose(tester, 'department', 'ancash', '02');
      expect(selection.departmentCode, '02');
      expect(selection.provinceCode, isNull);
      expect(selection.districtCode, isNull);
      expect(find.text('Áncash'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Edición controlada, selección parcial y estado deshabilitado', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    final selector = GlobalKey<FormFieldState<PeruLocationSelection>>();
    var value = const PeruLocationSelection(
      departmentCode: '15',
      provinceCode: '1501',
    );
    var enabled = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return PeruLocationSelector(
                  key: selector,
                  catalog: catalog,
                  value: value,
                  maxLevel: PeruLocationLevel.province,
                  isRequired: true,
                  enabled: enabled,
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isTrue);
    expect(find.byKey(const ValueKey('peru_location_district')), findsNothing);
    update(() {
      value = const PeruLocationSelection(
        departmentCode: '02',
        provinceCode: '0201',
      );
      enabled = false;
    });
    await tester.pumpAndSettle();
    expect(selector.currentState!.value?.provinceCode, '0201');
    expect(find.text('Huaraz'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('peru_location_department')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('peru_location_province')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selector opcional por departamento con texto al 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final form = GlobalKey<FormState>();
    final selector = GlobalKey<FormFieldState<PeruLocationSelection>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: SingleChildScrollView(
              child: PeruLocationSelector(
                key: selector,
                catalog: catalog,
                maxLevel: PeruLocationLevel.department,
              ),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isTrue);
    expect(find.byKey(const ValueKey('peru_location_province')), findsNothing);
    await choose(tester, 'department', 'lambayeque', '14');
    expect(selector.currentState!.value?.departmentCode, '14');
    expect(selector.currentState!.value?.provinceCode, isNull);
    expect(tester.takeException(), isNull);
  });

  test(
    'Fallar el registro remoto conserva la ubicación elegida para reintentar',
    () async {
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final remote = SupabaseRemoteGateway();
      final controller = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await controller.initialize(startWithActiveSession: false);
      await expectLater(
        controller.registerAndSignIn(
          alias: 'Prueba',
          email: 'offline@example.test',
          password: 'clave-de-prueba',
          neighborhood: 'Chachapoyas',
          sector: 'Referencia',
          districtUbigeo: '010101',
          approxLat: null,
          approxLng: null,
          useGpsApprox: false,
        ),
        throwsStateError,
      );
      expect(controller.currentUser, isNull);
      expect((await db.readManualLocation())?['district_ubigeo'], '010101');
      controller.dispose();
      final restored = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await restored.initialize(startWithActiveSession: false);
      expect(restored.activeDistrictUbigeo, '010101');
      expect(restored.activeLat, isNull);
      restored.dispose();
    },
  );

  testWidgets('Registro, perfil y publicaciones guardan UBIGEO sin conexión', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false)
      ..simulateNetworkOffline = true;
    final controller = AppController(
      database: db,
      remoteGateway: remote,
      outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
    );
    await controller.initialize(startWithActiveSession: false);
    controller.navigateTo(AppSection.autenticacion);
    await tester.pumpWidget(
      NexoNeighborhoodApp(
        appController: controller,
        accessibilityController: AccessibilityController(),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'department', 'lima', '15');
    await choose(tester, 'province', 'lima', '1501');
    await choose(tester, 'district', 'la molina', '150114');
    // INEI does not provide a usable capital coordinate for this entry.
    expect(catalog.district('150114')?.capitalLat, isNull);
    final register = find.byKey(const Key('tab_register_mode'));
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();
    for (final (key, text) in [
      ('input_auth_alias', 'Vecina de prueba'),
      ('input_auth_email', 'ubigeo@example.test'),
      ('input_auth_password', 'password-prueba'),
    ]) {
      final field = find.byKey(Key(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }
    final submit = find.byKey(const Key('btn_submit_auth'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(controller.currentUser?.districtUbigeo, '150114');
    expect(controller.currentUser?.approxLat, isNull);
    expect(controller.currentUser?.approxLng, isNull);
    final pub = await controller.submitPublication(
      kind: PublicationKind.favorSolicitud,
      category: 'general',
      title: 'Ayuda de prueba',
      description: 'Solicitud local sin conexión',
    );
    expect(pub.districtUbigeo, '150114');
    expect(pub.approxLat, isNull);
    expect(pub.distanceFrom(lat: -12.076, lng: -77.063), isNull);
    final operation = (await db.listOutboxForUser(controller.currentUser!.id))
        .firstWhere((entry) => entry.entityType == 'publication');
    expect(operation.decodePayload()['district_ubigeo'], '150114');
    expect(operation.decodePayload()['approx_lat'], isNull);
    controller.navigateTo(AppSection.autenticacion);
    await tester.pumpAndSettle();
    expect(find.text('La Molina'), findsOneWidget);
    final reference = find.byKey(const Key('input_location_reference'));
    await tester.ensureVisible(reference);
    await tester.enterText(reference, 'Referencia conservada');
    final save = find.byKey(const Key('btn_save_manual_zone'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(controller.currentUser?.districtUbigeo, '150114');
    expect(controller.currentUser?.sector, 'Referencia conservada');
    expect(controller.currentUser?.approxLat, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets(
    'Un perfil antiguo conserva texto y coordenadas sin inferir UBIGEO',
    (tester) async {
      final db = LocalSqliteDatabase(
        engine: InMemoryTransactionalStoreEngine(),
      );
      final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false)
        ..simulateNetworkOffline = true;
      final controller = AppController(
        database: db,
        remoteGateway: remote,
        outboxSyncService: OutboxSyncService(
          database: db,
          remoteGateway: remote,
        ),
      );
      await controller.initialize();
      final before = controller.currentUser!;
      controller.navigateTo(AppSection.autenticacion);
      await tester.pumpWidget(
        NexoNeighborhoodApp(
          appController: controller,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.pumpAndSettle();
      final selector = tester.state<FormFieldState<PeruLocationSelection>>(
        find.byType(PeruLocationSelector),
      );
      expect(selector.value?.districtCode, isNull);
      final save = find.byKey(const Key('btn_save_manual_zone'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(controller.currentUser?.districtUbigeo, isNull);
      expect(controller.currentUser?.neighborhood, before.neighborhood);
      expect(controller.currentUser?.sector, before.sector);
      expect(controller.currentUser?.approxLat, before.approxLat);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  test('Migración SQLite v1 conserva registros, borradores y cola; UBIGEO persiste al reabrir', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('peru-locations-');
    final path = '${directory.path}/old.db';
    final fixture = await File('test/fixtures/sqlite_v1.sql').readAsString();
    final oldDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          for (final sql in fixture.split(';')) {
            if (sql.trim().isNotEmpty) await db.execute(sql);
          }
        },
      ),
    );
    final user = UserProfile(
      id: EntityId.create(),
      alias: 'Perfil anterior',
      neighborhood: 'Pueblo Libre',
      sector: 'Referencia anterior',
      approxLat: -12.076,
      approxLng: -77.063,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final oldProfile = user.toSqlMap()..remove('district_ubigeo');
    await oldDb.insert('profiles_local', oldProfile);
    final publication = Publication(
      id: EntityId.create(),
      clientMutationId: EntityId.create(),
      ownerUserId: user.id,
      authorId: user.id,
      authorAlias: user.alias,
      kind: PublicationKind.favorSolicitud,
      category: 'general',
      title: 'Título anterior',
      description: 'Texto anterior',
      neighborhood: user.neighborhood,
      sector: user.sector,
      approxLat: user.approxLat,
      approxLng: user.approxLng,
      createdAt: user.updatedAt,
      updatedAt: user.updatedAt,
    );
    final oldPublication = publication.toSqlMap()
      ..remove('district_ubigeo')
      ..remove('share_service_location')
      ..remove('service_lat')
      ..remove('service_lng')
      ..remove('service_address');
    await oldDb.insert('publications_local', oldPublication);
    final originalPayload = jsonEncode(oldPublication);
    await oldDb.insert(
      'outbox_operations',
      OutboxOperation(
        operationId: publication.clientMutationId,
        ownerUserId: user.id,
        entityType: 'publication',
        entityId: publication.id,
        action: 'upsert',
        payloadJson: originalPayload,
        syncStatus: SyncStatus.pendiente,
        createdAt: user.updatedAt,
        updatedAt: user.updatedAt,
      ).toSqlMap(),
    );
    await oldDb.insert(
      'drafts_local',
      FormDraft(
          draftKey: 'previous',
          ownerUserId: user.id,
          kind: PublicationKind.favorSolicitud,
          title: 'Borrador anterior',
          description: 'No perder este texto',
          updatedAt: user.updatedAt,
        ).toSqlMap()
        ..remove('location_json')
        ..['draft_key'] = '${user.id}::previous',
    );
    await oldDb.close();
    final engine = SqfliteStoreEngine(databaseFileName: path);
    final db = LocalSqliteDatabase(engine: engine);
    await db.initAndSeedDemoData(seedDemo: false);
    final restored = (await db.getUserProfile(user.id))!;
    expect(restored.districtUbigeo, isNull);
    expect(restored.neighborhood, user.neighborhood);
    expect(restored.sector, user.sector);
    expect(restored.approxLat, user.approxLat);
    expect(
      (await db.getDraft(
        ownerUserId: user.id,
        draftKey: 'previous',
      ))?.description,
      'No perder este texto',
    );
    expect(
      (await db.listOutboxForUser(user.id)).single.payloadJson,
      originalPayload,
    );
    await db.saveUserProfile(
      restored.copyWith(
        districtUbigeo: '120307',
        neighborhood: 'Sangani',
        clearCoordinates: true,
      ),
      queueSync: true,
    );
    await db.saveManualLocation({
      'district_ubigeo': '150114',
      'neighborhood': 'La Molina',
      'sector': 'Referencia',
      'approx_lat': null,
      'approx_lng': null,
      'use_gps_approx': 0,
    });
    await engine.close();
    final reopenedEngine = SqfliteStoreEngine(databaseFileName: path);
    final reopened = LocalSqliteDatabase(engine: reopenedEngine);
    await reopened.initAndSeedDemoData(seedDemo: false);
    expect((await reopened.getUserProfile(user.id))?.districtUbigeo, '120307');
    expect((await reopened.getUserProfile(user.id))?.approxLat, isNull);
    expect((await reopened.readManualLocation())?['district_ubigeo'], '150114');
    final controller = AppController(
      database: reopened,
      remoteGateway: _OldProfileGateway(user),
      outboxSyncService: OutboxSyncService(
        database: reopened,
        remoteGateway: _OldProfileGateway(user),
      ),
    );
    await controller.initialize();
    expect(
      controller.currentUser?.districtUbigeo,
      '120307',
      reason: 'Una descarga anterior no puede reemplazar una edición pendiente',
    );
    controller.dispose();
    await reopenedEngine.close();
    await directory.delete(recursive: true);
  });
}

class _OldProfileGateway extends SupabaseRemoteGateway {
  _OldProfileGateway(this.profile) : super(forceSupabaseAvailable: false);
  final UserProfile profile;
  @override
  Future<UserProfile?> getCurrentSessionProfile() async => profile;
}
