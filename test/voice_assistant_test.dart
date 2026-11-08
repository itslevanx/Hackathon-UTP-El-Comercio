import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/features/voice_assistant/voice_analysis.dart';
import 'package:hackathon_utp_el_comercio/features/voice_assistant/voice_controller.dart';
import 'package:hackathon_utp_el_comercio/features/voice_assistant/voice_audio.dart';
import 'package:hackathon_utp_el_comercio/features/voice_assistant/voice_model_store.dart';
import 'package:hackathon_utp_el_comercio/features/voice_assistant/voice_assistant_screen.dart';
import 'package:hackathon_utp_el_comercio/features/publish/publish_screen.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

class TestModels extends VoiceModelStore {
  TestModels({this.ready = true});
  final bool ready;
  @override
  Future<String?> readyPath() async => ready ? 'local-model.bin' : null;
}

class TestAudio implements VoiceAudio {
  TestAudio({this.deny = false});
  final bool deny;
  bool disposed = false;
  int starts = 0;
  @override
  Future<void> start() async {
    starts++;
    if (deny) throw StateError('permission');
  }

  @override
  Future<String?> stop() async => 'private-audio.wav';
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class TestEngine implements VoiceTranscriber {
  Completer<String>? pending;
  bool fail = false;
  int calls = 0;
  @override
  Future<String> transcribe(String model, String audio) async {
    calls++;
    if (fail) throw StateError('native');
    return pending == null ? 'Necesitamos agua potable' : await pending!.future;
  }

  @override
  Future<void> cancel() async {
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(StateError('cancel'));
    }
  }
}

class BadDownload extends VoiceModelStore {
  BadDownload(this.target)
    : super(
        clientFactory: () =>
            MockClient((_) async => http.Response('invalid', 200)),
      );
  final File target;
  @override
  Future<File> get file async => target;
}

Future<AppController> app() async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VoiceAnalyzer analyzer;
  late PeruLocationCatalog catalog;
  setUpAll(() async {
    catalog = await PeruLocationCatalog.load();
    analyzer = VoiceAnalyzer(catalog);
  });
  test('Normaliza tildes, espacios y español peruano', () {
    expect(
      normalizeVoiceText('  Necesitámos ÁGUA\n potable  '),
      'necesitamos agua potable',
    );
  });
  final examples = {
    'Se está inundando mi calle': 'inundacion',
    'Necesitamos agua potable': 'agua',
    'Hay una persona atrapada': 'asistencia',
    'Se fue la luz en mi barrio': 'corte_servicios',
    'No hay ningún incendio, solo humo de una parrilla': 'general',
    'Necesito llevar alimentos a una familia': 'alimentos',
    'No tenemos agua potable': 'agua',
    'No hay nadie atrapado': 'general',
    'Sin incendio, solo humo': 'general',
    'Estamos sin agua potable': 'agua',
    'Creo que hubo un derrumbe, pero no estoy seguro': 'derrumbe',
    'Hay un sismo en la zona': 'sismo',
    'Hubo un choque en la avenida': 'accidente',
  };
  for (final e in examples.entries) {
    test('Clasifica: ${e.key}', () {
      expect(analyzer.analyze(e.key).category, e.value);
    });
  }
  test(
    'Prioridad crítica explicable, incertidumbre y negaciones no alarmistas',
    () {
      expect(
        analyzer.analyze('Hay una persona atrapada').attention,
        VoiceAttention.inmediata,
      );
      final uncertain = analyzer.analyze(
        'Creo que hubo un derrumbe, pero no estoy seguro',
      );
      expect(uncertain.uncertain, true);
      expect(uncertain.attention, VoiceAttention.media);
      expect(
        analyzer
            .analyze('No hay ningún incendio, solo humo de una parrilla')
            .attention,
        VoiceAttention.baja,
      );
      expect(
        analyzer.analyze('No estoy atrapado').attention,
        VoiceAttention.baja,
      );
      expect(
        analyzer.analyze('No necesito llevar alimentos').resources,
        isEmpty,
      );
      expect(
        analyzer.analyze('La persona no respira').attention,
        VoiceAttention.inmediata,
      );
    },
  );
  test('Vacío y transcripción incompleta solicitan revisión', () {
    final empty = analyzer.analyze('  ');
    expect(empty.category, 'general');
    expect(empty.missing, contains('Descripción'));
    expect(
      analyzer.analyze('allá por esa cosa').attention,
      VoiceAttention.baja,
    );
  });
  test('Extrae recursos y cantidades explícitas sin inventar existencias', () {
    final result = analyzer.analyze(
      'Necesitamos cinco litros de agua potable y 2 palas para tres familias',
    );
    expect(result.resources, containsAll(['agua', 'herramientas']));
    expect(
      result.quantities,
      containsAll(['5 litros', '2 palas', '3 familias']),
    );
    expect(analyzer.analyze('Necesito agua').quantities, isEmpty);
  });
  test(
    'UBIGEO reconoce nombres y mantiene las ubicaciones ambiguas para revisión',
    () {
      final result = analyzer.analyze('Derrumbe en Pueblo Libre');
      expect(result.districts.map((e) => e.name), everyElement('Pueblo Libre'));
      expect(result.districts.any((e) => e.code == '150121'), true);
      final several = analyzer.analyze(
        'Necesitamos ayuda en Pueblo Libre y Comas',
      );
      expect(
        several.districts.map((e) => e.name),
        containsAll(['Pueblo Libre', 'Comas']),
      );
      expect(
        analyzer.analyze('Ayuda en una calle desconocida').districts,
        isEmpty,
      );
    },
  );
  test('Reglas de prioridad se pueden ampliar sin cambiar widgets', () {
    final custom = VoiceAnalyzer(
      catalog,
      rules: const VoiceRules(
        criticalTerms: [r'\briesgo especial\b'],
        urgentTerms: [],
      ),
    );
    expect(
      custom.analyze('Tenemos riesgo especial').attention,
      VoiceAttention.inmediata,
    );
  });
  test('Micrófono denegado libera recursos y no inicia inferencia', () async {
    final audio = TestAudio(deny: true);
    final engine = TestEngine();
    final c = VoiceController(
      audioFactory: () => audio,
      transcriber: engine,
      models: TestModels(),
    );
    await c.checkModel();
    await c.start();
    expect(c.stage, VoiceStage.error);
    expect(audio.disposed, true);
    expect(engine.calls, 0);
    c.dispose();
  });
  test(
    'Transcribe localmente una sola vez y elimina audio al terminar o fallar',
    () async {
      for (final fail in [false, true]) {
        final audio = TestAudio();
        final engine = TestEngine()..fail = fail;
        final c = VoiceController(
          audioFactory: () => audio,
          transcriber: engine,
          models: TestModels(),
        );
        await c.checkModel();
        await c.start();
        await c.start();
        expect(audio.starts, 1);
        await c.stop();
        expect(audio.disposed, true);
        expect(engine.calls, 1);
        expect(c.stage, fail ? VoiceStage.error : VoiceStage.review);
        c.dispose();
      }
    },
  );
  test(
    'Cancelar una inferencia descarta su resultado y libera la captura',
    () async {
      final audio = TestAudio();
      final engine = TestEngine()..pending = Completer<String>();
      final c = VoiceController(
        audioFactory: () => audio,
        transcriber: engine,
        models: TestModels(),
      );
      await c.checkModel();
      await c.start();
      final stopping = c.stop();
      await Future<void>.delayed(Duration.zero);
      await c.cancel();
      await stopping;
      expect(c.text, isEmpty);
      expect(c.stage, VoiceStage.idle);
      expect(audio.disposed, true);
      c.dispose();
    },
  );
  test(
    'Modelo ausente no descarga ni abre el micrófono automáticamente',
    () async {
      final audio = TestAudio();
      final c = VoiceController(
        audioFactory: () => audio,
        transcriber: TestEngine(),
        models: TestModels(ready: false),
      );
      await c.checkModel();
      await c.start();
      expect(audio.starts, 0);
      expect(c.modelPath, isNull);
      c.dispose();
    },
  );
  test(
    'Descarga inválida conserva el modelo previo y elimina parciales',
    () async {
      final dir = await Directory.systemTemp.createTemp('voice-model-test');
      final file = File('${dir.path}/model.bin');
      await file.writeAsString('previous');
      final model = BadDownload(file);
      await expectLater(model.download((_) {}), throwsStateError);
      expect(await file.readAsString(), 'previous');
      expect(await File('${file.path}.part').exists(), false);
      await dir.delete(recursive: true);
    },
  );
  test('Prefill de otro distrito no reutiliza GPS ni altera la zona del perfil; queda en cola offline', () async {
    final c = await app();
    addTearDown(c.dispose);
    final previous = c.activeDistrictUbigeo;
    final p = await c.submitPublication(
      kind: PublicationKind.emergenciaSolicitud,
      category: 'derrumbe',
      title: 'Reporte revisado',
      description: 'Revisión del vecino',
      districtUbigeoOverride: '150110',
      priorityOverride: PublicationPriority.urgente,
    );
    expect(p.districtUbigeo, '150110');
    expect(p.approxLat, isNull);
    expect(p.approxLng, isNull);
    expect(c.activeDistrictUbigeo, previous);
    expect(p.priority, PublicationPriority.urgente);
    expect(p.syncStatus, SyncStatus.pendiente);
    expect(
      (await c.database.listOutboxForUser(c.currentUser!.id))
          .any((op) => op.entityId == p.id),
      true,
    );
  });
  testWidgets(
    'Dictado prepara el formulario sin publicar; el envío requiere pulsar Enviar',
    (tester) async {
      final c = await app();
      addTearDown(c.dispose);
      final voice = VoiceController(
        models: TestModels(ready: false),
        transcriber: TestEngine(),
      );
      final before = (await c.database.listOutboxForUser(c.currentUser!.id))
          .length;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoiceAssistantScreen(app: c, voice: voice),
                  ),
                ),
                child: const Text('Abrir voz'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir voz'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('voice_transcript')),
        'Necesitamos cinco litros de agua en Santiago de Surco',
      );
      await tester.pumpAndSettle();
      expect(
        (await c.database.listOutboxForUser(c.currentUser!.id)).length,
        before,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('voice_continue')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('voice_continue')));
      await tester.pumpAndSettle();
      expect(c.currentSection, AppSection.publicarRapido);
      expect(
        (await c.database.listOutboxForUser(c.currentUser!.id)).length,
        before,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PublishScreen(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Revisa el reporte preparado por voz'),
        findsOneWidget,
      );
      final submit = find.byKey(const Key('btn_submit_publication'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(
        (await c.database.listOutboxForUser(c.currentUser!.id)).length,
        greaterThan(before),
      );
      expect(
        c.publications.any(
          (p) => p.category == 'agua' && p.districtUbigeo == '150140',
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Micrófono central y nav conservan accesibilidad con texto ampliado',
    (tester) async {
      final c = await app();
      addTearDown(c.dispose);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final accessibility = AccessibilityController();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Conecta2App(appController: c, accessibilityController: accessibility),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav_voz')), findsOneWidget);
      expect(find.byKey(const Key('nav_chats')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'El asistente admite texto al 200 % sin desbordar sus controles',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await app();
      addTearDown(c.dispose);
      final voice = VoiceController(
        models: TestModels(ready: false),
        transcriber: TestEngine(),
      )..text = 'Hay una persona atrapada en Santiago de Surco';
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: VoiceAssistantScreen(app: c, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('voice_continue')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
