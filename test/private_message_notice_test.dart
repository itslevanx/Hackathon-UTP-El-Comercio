import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_utp_el_comercio/core/database/local_sqlite_database.dart';
import 'package:hackathon_utp_el_comercio/core/notifications/private_message_notice.dart';
import 'package:hackathon_utp_el_comercio/core/state/app_controller.dart';
import 'package:hackathon_utp_el_comercio/core/sync/outbox_sync_service.dart';
import 'package:hackathon_utp_el_comercio/core/sync/supabase_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Solo acepta avisos de mensajes privados con identificadores válidos',
    () {
      const data = {
        'type': 'private_message',
        'conversation_id': 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
        'recipient_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'message_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      };
      final notice = PrivateMessageNotice.fromData(data)!;
      expect(notice.conversationId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(notice.recipientId, data['recipient_id']);
      expect(notice.messageId, data['message_id']);
      expect(
        PrivateMessageNotice.fromData({...data, 'type': 'emergency_group'}),
        isNull,
      );
      expect(
        PrivateMessageNotice.fromData({...data, 'recipient_id': 'otra cuenta'}),
        isNull,
      );
      expect(
        PrivateMessageNotice.fromData({...data, 'message_id': null}),
        isNull,
      );
    },
  );

  test('El aviso abre un chat solo para la sesión destinataria', () async {
    final db = LocalSqliteDatabase(engine: InMemoryTransactionalStoreEngine());
    final remote = SupabaseRemoteGateway(forceSupabaseAvailable: false);
    final controller = AppController(
      database: db,
      remoteGateway: remote,
      outboxSyncService: OutboxSyncService(database: db, remoteGateway: remote),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final service = controller.publications.firstWhere(
      (item) => item.id == 'pub-demo-servicio-luis',
    );
    final thread = await controller.requestContactWithProvider(
      publication: service,
      initialMessage: 'Consulta de prueba.',
    );
    final historicalId = '${thread.id}-historico';
    await db.mergeCommunitySnapshot({
      'conversations': [
        {
          ...thread.toSqlMap(),
          'id': historicalId,
          'client_mutation_id': historicalId,
          'publication_id': 'otra-publicacion',
          'sync_status': 'confirmado',
        },
      ],
    });
    await controller.refreshAllLocalData();
    final userId = controller.currentUser!.id;
    expect(
      controller.userConversations.any((t) => t.id == historicalId),
      isFalse,
    );
    await controller.hideChat(controller.chatKeyFor(thread));
    controller.goHome();

    expect(
      await controller.openPrivateChatFromPush(thread.id, 'otra-cuenta'),
      isFalse,
    );
    expect(controller.currentSection, AppSection.inicio);
    expect(
      await controller.openPrivateChatFromPush(historicalId, userId),
      isTrue,
    );
    expect(controller.selectedConversation?.id, historicalId);
    expect(controller.currentSection, AppSection.chatConversacion);
    expect(controller.isViewingPrivateChat(thread.id), isTrue);
    expect(await controller.openPrivateChatFromPush(thread.id, userId), isTrue);
    expect(controller.selectedConversation?.id, historicalId);
  });
}
