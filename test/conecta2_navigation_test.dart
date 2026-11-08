import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/config/app_config.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

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
  setUpAll(PeruLocationCatalog.load);
  testWidgets(
    'Conecta2 muestra cuatro pestañas y Chats abre las conversaciones del usuario',
    (tester) async {
      final c = await app();
      addTearDown(c.dispose);
      final service = c.publications.firstWhere(
        (p) => p.kind.isService && p.authorId != c.currentUser!.id,
      );
      final thread = await c.database.openOrGetConversation(
        id: 'my-chat',
        clientMutationId: 'my-chat-op',
        publication: service,
        participantId: c.currentUser!.id,
        participantAlias: c.currentUser!.alias,
      );
      await c.database.openOrGetConversation(
        id: 'foreign-chat',
        clientMutationId: 'foreign-chat-op',
        publication: service,
        participantId: 'other-neighbor',
        participantAlias: 'Otro vecino',
      );
      await c.refreshAllLocalData();
      await tester.pumpWidget(
        Conecta2App(
          appController: c,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.pumpAndSettle();
      expect(AppConfig.appName, 'Conecta2');
      expect(find.text('Conecta2'), findsOneWidget);
      for (final key in ['inicio', 'servicios', 'actividad', 'chats']) {
        expect(find.byKey(ValueKey('nav_$key')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('nav_chats')));
      await tester.pumpAndSettle();
      expect(c.currentSection, AppSection.chatLista);
      expect(
        find.byKey(const Key('card_conversation_my-chat')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('card_conversation_foreign-chat')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('card_conversation_my-chat')));
      await tester.pumpAndSettle();
      expect(c.selectedConversation?.id, thread.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Las cuatro pestañas son accesibles con texto ampliado en pantalla estrecha',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await app();
      addTearDown(c.dispose);
      final a = AccessibilityController();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        Conecta2App(appController: c, accessibilityController: a),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav_chats')));
      await tester.pumpAndSettle();
      expect(c.currentSection, AppSection.chatLista);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
