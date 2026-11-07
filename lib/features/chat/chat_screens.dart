import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Listado de conversaciones privadas contextuales del vecino autenticado.
/// Solo muestra conversaciones donde el usuario es autor de la publicación o
/// participante directo (un tercero ajeno no puede leer ni listar).
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final threads = controller.userConversations;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Conversaciones Privadas Contextuales',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Cada conversación está ligada a un servicio o solicitud del barrio y es privada exclusivamente entre los dos vecinos participantes.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (threads.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSoft),
              ),
              child: const Text(
                'Aún no tienes conversaciones activas. Abre cualquier servicio o favor del barrio para enviar una solicitud de contacto.',
                style: TextStyle(fontSize: 17, color: AppTheme.textSecondary),
              ),
            )
          else
            for (final t in threads) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  key: Key('card_conversation_${t.id}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => controller.openConversation(t),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SyncStatusBadge(status: t.syncStatus),
                        const SizedBox(height: 8),
                        Text(
                          t.publicationTitle,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Participantes: ${t.publicationAuthorAlias} y ${t.participantAlias}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.actionGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// Hilo de mensajes privados entre dos participantes autenticados.
/// Cumple estrictamente la regla del encargo:
/// "Mensajes offline no se envían: indica que requieren conexión y conserva el
/// texto como borrador si procede."
class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<ChatMessage> _messages = const [];
  String? _offlineOrErrorNotice;
  StreamSubscription<ChatMessage>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadMessagesAndDraft();
  }

  Future<void> _loadMessagesAndDraft() async {
    final conv = widget.controller.selectedConversation;
    final user = widget.controller.currentUser;
    if (conv == null || user == null) return;

    try {
      final list = await widget.controller.database.listMessagesForConversation(
        conversationId: conv.id,
        actingUserId: user.id,
      );
      final draft = await widget.controller.database.getDraft(
        ownerUserId: user.id,
        draftKey: 'chat_${conv.id}',
      );

      _realtimeSub ??= widget.controller.remoteGateway
          .watchConversationMessages(conv.id)
          .listen(
            (message) async {
              try {
                await widget.controller.database.recordOnlineMessage(
                  id: message.id,
                  clientMutationId: message.clientMutationId,
                  conversationId: message.conversationId,
                  senderId: message.senderId,
                  senderAlias: message.senderAlias,
                  body: message.body,
                  syncStatus: SyncStatus.confirmado,
                );
                if (mounted) await _loadMessagesAndDraft();
              } catch (e) {
                if (mounted) {
                  setState(
                    () => _offlineOrErrorNotice = 'No se pudo actualizar la conversación. Reintenta al recuperar conexión.',
                  );
                }
              }
            },
            onError: (Object error) {
              if (mounted) {
                setState(
                  () => _offlineOrErrorNotice =
                      'No se pudo conectar al chat. Tu texto sigue disponible.',
                );
              }
            },
          );

      if (mounted) {
        setState(() {
          _messages = list;
          if (draft != null && _msgController.text.isEmpty) {
            _msgController.text = draft.description;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _offlineOrErrorNotice = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final conv = widget.controller.selectedConversation;
    if (conv == null) return;
    setState(() {
      _offlineOrErrorNotice = null;
    });
    try {
      await widget.controller.sendChatMessageInThread(
        thread: conv,
        text: _msgController.text,
      );
      _msgController.clear();
      await _loadMessagesAndDraft();
    } catch (e) {
      if (mounted) {
        setState(() {
          _offlineOrErrorNotice = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final conv = c.selectedConversation;
    if (conv == null) {
      return const Center(child: Text('Selecciona una conversación privada.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conv.publicationTitle,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chat privado entre ${conv.publicationAuthorAlias} y ${conv.participantAlias}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.actionGreen,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sugerencia de seguridad: acuerden encontrarse en un punto público e iluminado del barrio (ej. Plaza Bolívar o Parque Candamo).',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          if (c.isOfflineMode || _offlineOrErrorNotice != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('banner_chat_offline_notice'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.amberWarning, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: AppTheme.amberWarning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _offlineOrErrorNotice ?? 'Estás sin conexión. Los mensajes de chat requieren conexión activa y no se envían sin internet; tu texto se conservará como borrador.',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.amberWarning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mensajes (${_messages.length}):',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                if (_messages.isEmpty)
                  const Text(
                    'Aún no hay mensajes enviados con conexión en esta conversación.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  )
                else
                  for (final m in _messages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: m.senderId == c.currentUser?.id
                              ? const Color(0xFFDDF7E8)
                              : AppTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.senderAlias,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.actionGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.body,
                              style: const TextStyle(
                                fontSize: 17,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_chat_message_body'),
                  controller: _msgController,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Escribe tu mensaje',
                    hintText:
                        'Ej. Nos vemos a las 4:00 pm frente a la pérgola.',
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: ElevatedButton.icon(
                    key: const Key('btn_send_chat_message'),
                    onPressed: _handleSend,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Enviar mensaje'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
