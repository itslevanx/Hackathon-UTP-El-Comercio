import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/models/emergency_group_message.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/features/chat/message_bubble.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

import 'conecta2_navigation_test.dart' as fixture;
import 'emergency_group_chat_test.dart' as group_fixture;

Future<ConversationThread> thread(AppController c) =>
    c.database.openOrGetConversation(
      id: 'private-chat',
      clientMutationId: 'private-op',
      publication: c.publications.firstWhere(
        (p) => p.authorId != c.currentUser!.id && p.kind.isService,
      ),
      participantId: c.currentUser!.id,
      participantAlias: c.currentUser!.alias,
    );

Widget app(AppController c) => Conecta2App(
  appController: c,
  accessibilityController: AccessibilityController(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test('Fijar y quitar chats se aplica solo a la cuenta y no toca mensajes ni envíos', () async {
    final c = await fixture.app();
    addTearDown(c.dispose);
    final t = await thread(c);
    final p = await group_fixture.emergency(c);
    await c.openEmergencyGroup(p);
    await c.database.recordOnlineMessage(
      id: 'existing',
      clientMutationId: 'existing-op',
      conversationId: t.id,
      senderId: c.currentUser!.id,
      senderAlias: 'Vecina',
      body: 'Mensaje conservado',
      syncStatus: SyncStatus.confirmado,
      createdAt: DateTime.now(),
    );
    final pending = (await c.database.listOutboxForUser(c.currentUser!.id))
        .length;
    await c.setChatPinned('private:${t.id}', true);
    await c.setChatPinned('group:${p.id}', true);
    expect(c.isChatPinned('private:${t.id}'), isTrue);
    await c.hideChat('private:${t.id}');
    await c.hideChat('group:${p.id}');
    expect(c.userConversations, isEmpty);
    expect(c.emergencyGroupChats, isEmpty);
    expect(c.isChatPinned('private:${t.id}'), isFalse);
    expect(
      (await c.database.readChatPreferences('otra-cuenta')).hidden,
      isEmpty,
    );
    expect(
      await c.database.listConversationsForUser(c.currentUser!.id),
      hasLength(1),
    );
    expect(
      (await c.database.listOutboxForUser(c.currentUser!.id)).length,
      pending,
    );
    expect(
      (await c.database.listMessagesForConversation(
        conversationId: t.id,
        actingUserId: c.currentUser!.id,
      )).single.body,
      'Mensaje conservado',
    );
    await c.refreshAllLocalData();
    expect(c.userConversations, isEmpty);
    await c.openConversation(t);
    await c.openEmergencyGroup(p);
    expect(c.userConversations, hasLength(1));
    expect(c.emergencyGroupChats, hasLength(1));
    await expectLater(c.hideChat('private:ajeno'), throwsStateError);
    await c.signOut();
    expect(c.isChatPinned('group:${p.id}'), isFalse);
  });
  test(
    'SQLite conserva preferencias de privados y grupos por cuenta al reabrir',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp(
        'conecta2-chat-preferences-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/test.db';
      final first = SqfliteStoreEngine(databaseFileName: path);
      final db = LocalSqliteDatabase(engine: first);
      await db.initAndSeedDemoData(seedDemo: false);
      await db.saveChatPreference(
        owner: 'owner',
        chatKey: 'private:one',
        hidden: true,
      );
      await db.saveChatPreference(
        owner: 'owner',
        chatKey: 'group:two',
        pinned: true,
      );
      await first.close();
      final second = SqfliteStoreEngine(databaseFileName: path);
      addTearDown(second.close);
      final reopened = LocalSqliteDatabase(engine: second);
      await reopened.initAndSeedDemoData(seedDemo: false);
      final prefs = await reopened.readChatPreferences('owner');
      expect(prefs.hidden, contains('private:one'));
      expect(prefs.pinned, contains('group:two'));
      expect((await reopened.readChatPreferences('other')).pinned, isEmpty);
    },
  );
  testWidgets(
    'Chats fija arriba grupos y privados y permite deshacer la eliminación personal',
    (tester) async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      await thread(c);
      final p = await group_fixture.emergency(c);
      await c.openEmergencyGroup(p);
      c.goHome();
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_chats')));
      await tester.pumpAndSettle();
      final menu = find.byKey(Key('chat_options_group:${p.id}'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fijar chat'));
      await tester.pumpAndSettle();
      expect(c.isChatPinned('group:${p.id}'), isTrue);
      expect(
        tester.getTopLeft(find.byKey(Key('emergency_group_${p.id}'))).dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const Key('card_conversation_private-chat')),
              )
              .dy,
        ),
      );
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar de mi lista'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('emergency_group_${p.id}')), findsNothing);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('emergency_group_${p.id}')), findsOneWidget);
      expect(c.isChatPinned('group:${p.id}'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'El perfil separa el punto y la referencia y no muestra cuentas de prueba',
    (tester) async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      c.navigateTo(AppSection.autenticacion);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btn_switch_to_maria')), findsNothing);
      expect(find.byKey(const Key('btn_switch_to_jorge')), findsNothing);
      expect(find.byKey(const Key('btn_sign_out')), findsOneWidget);
      final pin = find.byKey(const Key('btn_choose_profile_pin'));
      final reference = find.byKey(const Key('input_location_reference'));
      await tester.ensureVisible(reference);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(reference).dy - tester.getBottomLeft(pin).dy,
        greaterThanOrEqualTo(24),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Mis publicaciones permite editar y eliminar desde el perfil sin conexión',
    (tester) async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      final p = await group_fixture.emergency(c);
      c.navigateTo(AppSection.misActividades);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final edit = find.byKey(Key('edit_publication_${p.id}'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit_publication_title')),
        'Emergencia actualizada',
      );
      final save = find.byKey(const Key('save_publication_edit'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        c.myPublications.firstWhere((v) => v.id == p.id).title,
        'Emergencia actualizada',
      );
      final delete = find.byKey(Key('delete_publication_${p.id}'));
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(c.myPublications.where((v) => v.id == p.id), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'El grupo alinea mensajes propios a la derecha y vecinos a la izquierda',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await fixture.app();
      addTearDown(c.dispose);
      final p = await group_fixture.emergency(c);
      await c.openEmergencyGroup(p);
      await c.database.mergeEmergencyGroupMessages(c.currentUser!.id, [
        for (final mine in [true, false])
          EmergencyGroupMessage(
            id: mine ? 'mine' : 'theirs',
            clientMutationId: mine ? 'mine-op' : 'theirs-op',
            publicationId: p.id,
            senderId: mine ? c.currentUser!.id : 'neighbor',
            senderAlias: mine ? 'Mi cuenta' : 'Vecino',
            body: mine ? 'Mi mensaje' : 'Su mensaje',
            createdAt: DateTime.now(),
          ),
      ]);
      expect(await c.emergencyGroupHistory(p), hasLength(2));
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byKey(const Key('emergency_group_history')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.drag(scrollable, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      for (final mine in [true, false]) {
        final bubble = find.byKey(
          Key('group_message_${mine ? 'mine' : 'theirs'}'),
        );
        position.jumpTo(0);
        await tester.pumpAndSettle();
        for (var step = 0; step < 20 && bubble.evaluate().isEmpty; step++) {
          position.jumpTo(
            (position.pixels + 60).clamp(0, position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.widget<ConversationMessageBubble>(bubble).isMine, mine);
        final align = tester.widget<Align>(
          find.descendant(of: bubble, matching: find.byType(Align)).first,
        );
        expect(
          align.alignment,
          mine ? Alignment.centerRight : Alignment.centerLeft,
        );
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
