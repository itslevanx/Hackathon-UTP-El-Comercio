import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/accessibility/text_input_support.dart';
import '../../core/models/domain_models.dart';
import '../../core/models/emergency_group_message.dart';
import '../../core/state/app_controller.dart';
import '../shared/civic_widgets.dart';

class EmergencyGroupChatScreen extends StatefulWidget {
  const EmergencyGroupChatScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<EmergencyGroupChatScreen> createState() =>
      _EmergencyGroupChatScreenState();
}

class _EmergencyGroupChatScreenState extends State<EmergencyGroupChatScreen> {
  final _input = TextEditingController();
  List<EmergencyGroupMessage> _messages = [];
  Timer? _timer;
  StreamSubscription<void>? _updates;
  Publication? _publication;
  bool _busy = false, _sending = false, _olderAvailable = true;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _publication = widget.controller.selectedEmergencyGroup;
    final p = _publication;
    if (p != null) {
      _read();
      _restoreDraft();
      _refresh();
      _updates = widget.controller.remoteGateway
          .watchEmergencyGroup(p.id)
          .listen(
            (_) => _refresh(),
            onError: (Object _) {
              if (mounted) {
                setState(
                  () => _notice = 'No se pudo actualizar el grupo. Los mensajes guardados siguen disponibles.',
                );
              }
            },
          );
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    }
  }

  Future<void> _restoreDraft() async {
    final uid = widget.controller.currentUser?.id;
    final p = _publication;
    if (uid == null || p == null) return;
    final draft = await widget.controller.database.getDraft(
      ownerUserId: uid,
      draftKey: 'group_${p.id}',
    );
    if (mounted &&
        widget.controller.currentUser?.id == uid &&
        draft != null &&
        _input.text.isEmpty) {
      _input.text = draft.description;
    }
  }

  Future<void> _draft() async {
    final user = widget.controller.currentUser;
    final p = _publication;
    if (user == null || p == null) return;
    await widget.controller.database.saveDraft(
      FormDraft(
        draftKey: 'group_${p.id}',
        ownerUserId: user.id,
        kind: p.kind,
        title: p.title,
        description: _input.text,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _read() async {
    final p = _publication;
    if (p == null) return;
    final list = await widget.controller.emergencyGroupHistory(p);
    if (mounted) setState(() => _messages = list);
  }

  Future<void> _refresh({bool older = false}) async {
    if (_busy || !mounted || widget.controller.isOfflineMode) return;
    final p = _publication;
    if (p == null || widget.controller.selectedEmergencyGroup?.id != p.id) {
      return;
    }
    _busy = true;
    try {
      final page = await widget.controller.refreshEmergencyGroup(
        p,
        before: older ? _messages.firstOrNull : null,
      );
      if (older && mounted) {
        setState(() => _olderAvailable = page.length == 100);
      }
      await _read();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'No se pudo actualizar el grupo. Puedes leer los mensajes guardados.',
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _send() async {
    if (_sending || _input.text.trim().isEmpty) return;
    final p = _publication;
    final uid = widget.controller.currentUser?.id;
    if (p == null || uid == null) return;
    final body = _input.text;
    setState(() => _sending = true);
    try {
      await widget.controller.sendEmergencyGroupMessage(p, body);
      if (!mounted || widget.controller.currentUser?.id != uid) return;
      _input.clear();
      await widget.controller.database.deleteDraft(
        ownerUserId: uid,
        draftKey: 'group_${p.id}',
      );
      await _read();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'No se pudo enviar. Tu texto sigue disponible; revisa el estado de la emergencia.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _updates?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = c.selectedEmergencyGroup;
    if (p == null || !c.canViewEmergencyGroup(p)) {
      return const Center(
        child: Text('Este grupo ya no está disponible para tu distrito.'),
      );
    }
    final closed =
        p.status == PublicationStatus.resuelta ||
        p.status == PublicationStatus.cancelada;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (constraints.maxHeight > 260)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Chat grupal · Visible para vecinos del distrito',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: const Key('emergency_group_history'),
              reverse: true,
              padding: const EdgeInsets.all(12),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _messages.length + 1,
              itemBuilder: (ctx, index) {
                if (index == _messages.length) {
                  return Column(
                    children: [
                      const Text(
                        'Conversación del distrito. No compartas direcciones privadas ni datos sensibles de otras personas.',
                      ),
                      if (_messages.isEmpty)
                        const Text(
                          'Aún no hay mensajes. Puedes iniciar la coordinación con tus vecinos.',
                        ),
                      if (_messages.length >= 100 && _olderAvailable)
                        TextButton(
                          onPressed: _busy ? null : () => _refresh(older: true),
                          child: const Text('Ver mensajes anteriores'),
                        ),
                    ],
                  );
                }
                final m = _messages[_messages.length - index - 1];
                return Card(
                  key: ValueKey('group_message_${m.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.senderAlias,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(m.body, style: const TextStyle(fontSize: 18)),
                        Text(m.createdAt.toLocal().toString().substring(0, 16)),
                        if (!m.syncStatus.isConfirmed)
                          SyncStatusBadge(status: m.syncStatus),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _notice!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (c.isOfflineMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Sin conexión: los mensajes nuevos quedan pendientes en este teléfono.',
              ),
            ),
          if (closed)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Emergencia cerrada. El grupo queda disponible para lectura.',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_emergency_group_message'),
                      enabled: !_sending,
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 1000,
                      contextMenuBuilder: buildTextSelectionToolbar,
                      onTapOutside: dismissTextInput,
                      onChanged: (_) => _draft(),
                      decoration: const InputDecoration(
                        hintText: 'Mensaje para el grupo',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('send_emergency_group_message'),
                    tooltip: 'Enviar al grupo',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
