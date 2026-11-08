import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/accessibility/accessibility_controller.dart';
import 'package:hackathon_utp_el_comercio/core/geography/peru_location_catalog.dart';
import 'package:hackathon_utp_el_comercio/core/models/domain_models.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/main.dart';

import 'conecta2_navigation_test.dart' as fixture;
import 'emergency_group_chat_test.dart' as group_fixture;

Future<({Publication first, Publication second})> services(
  AppController c,
) async {
  final first = c.publications.firstWhere(
    (p) => p.kind.isService && p.authorId != c.currentUser!.id,
  );
  final second = Publication.fromSqlMap({
    ...first.toSqlMap(),
    'id': 'another-service',
    'client_mutation_id': 'another-service-op',
    'title': 'Otro servicio del mismo vecino',
    'is_demo': 0,
  });
  await c.database.mergeRemotePublications([second]);
  await c.refreshAllLocalData();
  return (first: first, second: second);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PeruLocationCatalog.load);
  test('Otro servicio de la misma persona reutiliza su chat y conserva el contexto y el borrador anterior', () async {
    final c = await fixture.app();
    addTearDown(c.dispose);
    final pubs = await services(c);
    final first = await c.requestContactWithProvider(
      publication: pubs.first,
      initialMessage: 'Consulta pendiente',
    );
    final second = await c.requestContactWithProvider(
      publication: pubs.second,
      initialMessage: 'Consulta del segundo servicio',
    );
    expect(second.id, first.id);
    expect(c.userConversations, hasLength(1));
    expect(
      (await c.database.listConversationsForUser(c.currentUser!.id)),
      hasLength(1),
    );
    final draft = await c.database.getDraft(
      ownerUserId: c.currentUser!.id,
      draftKey: 'chat_${first.id}',
    );
    expect(draft!.description, contains(pubs.second.title));
    expect(draft.description, contains('Consulta del segundo servicio'));
    expect(
      (await c.database.listDraftsForUser(c.currentUser!.id))
          .any((d) => d.description.contains('Consulta pendiente')),
      isTrue,
    );
    final reverse = Publication.fromSqlMap({
      ...pubs.first.toSqlMap(),
      'id': 'reverse-service',
      'author_id': c.currentUser!.id,
    });
    final otherDirection = await c.database.openOrGetConversation(
      id: 'not-created',
      clientMutationId: 'not-created-op',
      publication: reverse,
      participantId: pubs.first.authorId,
      participantAlias: pubs.first.authorAlias,
    );
    expect(otherDirection.id, first.id);
  });
  test(
    'Los hilos históricos se muestran juntos sin perder mensajes ni borradores',
    () async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      final pubs = await services(c);
      final first = await c.database.openOrGetConversation(
        id: 'old-one',
        clientMutationId: 'old-one-op',
        publication: pubs.first,
        participantId: c.currentUser!.id,
        participantAlias: c.currentUser!.alias,
      );
      final legacy = ConversationThread.fromSqlMap({
        ...first.toSqlMap(),
        'id': 'old-two',
        'client_mutation_id': 'old-two-op',
        'publication_id': pubs.second.id,
        'sync_status': 'confirmado',
      });
      await c.database.mergeCommunitySnapshot({
        'conversations': [legacy.toSqlMap()],
      });
      for (final t in [first, legacy]) {
        await c.database.recordOnlineMessage(
          id: 'message-${t.id}',
          clientMutationId: 'message-op-${t.id}',
          conversationId: t.id,
          senderId: t.participantId,
          senderAlias: t.participantAlias,
          body: 'Historial ${t.id}',
          syncStatus: SyncStatus.confirmado,
          createdAt: DateTime.now(),
        );
        await c.database.saveDraft(
          FormDraft(
            draftKey: 'chat_${t.id}',
            ownerUserId: c.currentUser!.id,
            kind: PublicationKind.servicio,
            title: t.publicationTitle,
            description: 'Borrador ${t.id}',
            updatedAt: DateTime.now(),
          ),
        );
      }
      await c.refreshAllLocalData();
      expect(c.userConversations, hasLength(1));
      final combined = await c.database.listMessagesForConversation(
        conversationId: first.id,
        actingUserId: c.currentUser!.id,
      );
      expect(
        combined.map((m) => m.body),
        containsAll(['Historial old-one', 'Historial old-two']),
      );
      await c.openConversation(c.userConversations.single);
      final draft = await c.database.getDraft(
        ownerUserId: c.currentUser!.id,
        draftKey: 'chat_${c.selectedConversation!.id}',
      );
      expect(draft!.description, contains('Borrador old-one'));
      expect(draft.description, contains('Borrador old-two'));
      expect(
        await c.database.listConversationsForUser(c.currentUser!.id),
        hasLength(2),
      );
      await expectLater(
        c.database.listMessagesForConversation(
          conversationId: first.id,
          actingUserId: 'outsider',
        ),
        throwsStateError,
      );
    },
  );
  test('Las preferencias anteriores se trasladan al chat del vecino sin afectar otra cuenta', () async {
    final c = await fixture.app();
    addTearDown(c.dispose);
    final pubs = await services(c);
    final t = await c.database.openOrGetConversation(
      id: 'legacy-pref',
      clientMutationId: 'legacy-pref-op',
      publication: pubs.first,
      participantId: c.currentUser!.id,
      participantAlias: c.currentUser!.alias,
    );
    await c.database.saveChatPreference(
      owner: c.currentUser!.id,
      chatKey: 'private:${t.id}',
      pinned: true,
    );
    await c.refreshAllLocalData();
    expect(c.isChatPinned(c.chatKeyFor(t)), isTrue);
    expect(
      (await c.database.readChatPreferences(c.currentUser!.id)).pinned,
      contains('neighbor:${pubs.first.authorId}'),
    );
    expect((await c.database.readChatPreferences('outsider')).pinned, isEmpty);
  });
  testWidgets(
    'El último mensaje ordena privados y grupos; los fijados permanecen arriba',
    (tester) async {
      final c = await fixture.app();
      addTearDown(c.dispose);
      final pubs = await services(c);
      final t = await c.database.openOrGetConversation(
        id: 'order-chat',
        clientMutationId: 'order-chat-op',
        publication: pubs.first,
        participantId: c.currentUser!.id,
        participantAlias: c.currentUser!.alias,
      );
      final group = await group_fixture.emergency(c);
      await c.openEmergencyGroup(group);
      final later = DateTime.now().toUtc().add(const Duration(minutes: 5));
      await c.database.mergeChatActivity(c.currentUser!.id, {
        'neighbor:${pubs.first.authorId}': later,
        'group:${group.id}': later.subtract(const Duration(minutes: 1)),
      });
      await c.refreshAllLocalData();
      c.navigateTo(AppSection.chatLista);
      await tester.pumpWidget(
        Conecta2App(
          appController: c,
          accessibilityController: AccessibilityController(),
        ),
      );
      await tester.pumpAndSettle();
      final private = find.byKey(Key('card_conversation_${t.id}')),
          public = find.byKey(Key('emergency_group_${group.id}'));
      expect(
        tester.getTopLeft(private).dy,
        lessThan(tester.getTopLeft(public).dy),
      );
      await c.database.mergeChatActivity(c.currentUser!.id, {
        'group:${group.id}': later.add(const Duration(minutes: 1)),
      });
      await c.refreshAllLocalData();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(public).dy,
        lessThan(tester.getTopLeft(private).dy),
      );
      await c.setChatPinned(c.chatKeyFor(t), true);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(private).dy,
        lessThan(tester.getTopLeft(public).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
