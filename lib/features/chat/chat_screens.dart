import '../../core/accessibility/text_input_support.dart';

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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
  final ScrollController _historyController = ScrollController();
  bool _sending = false;
  List<ChatMessage> _messages = const [];
  String? _offlineOrErrorNotice;
  StreamSubscription<ChatMessage>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadMessagesAndDraft(restoreDraft: true);
  }

  Future<void> _loadMessagesAndDraft({bool restoreDraft = false}) async {
    final conv = widget.controller.selectedConversation;
    final user = widget.controller.currentUser;
    if (conv == null || user == null) return;

    try {
      final list = await widget.controller.database.listMessagesForConversation(
        conversationId: conv.id,
        actingUserId: user.id,
      );
      final draft = restoreDraft
          ? await widget.controller.database.getDraft(
              ownerUserId: user.id,
              draftKey: 'chat_${conv.id}',
            )
          : null;
      if (!mounted) return;

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
                  createdAt: message.createdAt,
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
    _historyController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final conv = widget.controller.selectedConversation;
    if (conv == null || _sending) return;
    final text = _msgController.text;
    setState(() {
      _sending = true;
      _offlineOrErrorNotice = null;
    });
    try {
      await widget.controller.sendChatMessageInThread(thread: conv, text: text);
      if (!mounted) return;
      if (_msgController.text == text) _msgController.clear();
      await _loadMessagesAndDraft();
      if (mounted && _historyController.hasClients) {
        _historyController.jumpTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _offlineOrErrorNotice = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final conv = c.selectedConversation;
    if (conv == null) {
      return const Center(child: Text('Selecciona una conversación privada.'));
    }

    final notice =
        _offlineOrErrorNotice ??
        (c.isOfflineMode
            ? 'Estás sin conexión. Tu mensaje se guardará como borrador.'
            : null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 260;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv.publicationTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Chat privado entre ${conv.publicationAuthorAlias} y ${conv.participantAlias}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: CustomScrollView(
                key: const Key('chat_message_history'),
                controller: _historyController,
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (notice != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        child: Text(
                          notice,
                          key: const Key('banner_chat_offline_notice'),
                          style: const TextStyle(color: AppTheme.amberWarning),
                        ),
                      ),
                    ),
                  if (_messages.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Aún no hay mensajes en esta conversación.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      sliver: SliverList.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message =
                              _messages[_messages.length - 1 - index];
                          final isMine = message.senderId == c.currentUser?.id;
                          return _MessageBubble(
                            key: ValueKey(message.id),
                            message: message,
                            isMine: isMine,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            Material(
              color: AppTheme.surfaceCard,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        contextMenuBuilder: buildTextSelectionToolbar,
                        onTapOutside: dismissTextInput,
                        key: const Key('input_chat_message_body'),
                        controller: _msgController,
                        minLines: 1,
                        maxLines: compact ? 1 : 2,
                        decoration: const InputDecoration(
                          hintMaxLines: 1,
                          hintText: 'Escribe tu mensaje',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('btn_send_chat_message'),
                      tooltip: 'Enviar mensaje',
                      onPressed: _sending ? null : _handleSend,
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFFBCEAD0) : const Color(0xFFE9EDF2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMine ? 'Tú' : message.senderAlias,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                message.body,
                style: const TextStyle(
                  fontSize: 17,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
