import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../core/notifications/private_message_notice.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/state/app_controller.dart';

/// Maneja los avisos de chat sin depender de que la lista de chats esté abierta.
class PrivateMessagePushListener extends StatefulWidget {
  const PrivateMessagePushListener({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppController controller;
  final Widget child;

  @override
  State<PrivateMessagePushListener> createState() =>
      _PrivateMessagePushListenerState();
}

class _PrivateMessagePushListenerState
    extends State<PrivateMessagePushListener> {
  final _service = PushNotificationService.instance;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  PrivateMessageNotice? _pending;
  String? _lastForegroundId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_openPending);
    _opened = _service.openedMessages.listen(
      _queueOpen,
      onError: (Object _) {},
    );
    _foreground = _service.foregroundMessages.listen(
      _showForeground,
      onError: (Object _) {},
    );
    unawaited(_readInitialMessage());
  }

  Future<void> _readInitialMessage() async {
    try {
      final message = await _service.takeInitialMessage();
      if (mounted && message != null) _queueOpen(message);
    } catch (_) {
      // El inicio normal sigue disponible si Firebase no entrega el aviso.
    }
  }

  void _queueOpen(RemoteMessage message) {
    final notice = PrivateMessageNotice.fromData(message.data);
    if (notice == null) return;
    _pending = notice;
    _openPending();
  }

  void _openPending() {
    final notice = _pending;
    final controller = widget.controller;
    final user = controller.currentUser;
    if (notice == null || user == null || controller.passwordRecoveryPending) {
      return;
    }
    _pending = null;
    if (user.id == notice.recipientId) {
      unawaited(Future<void>.microtask(() => _open(notice)));
    }
  }

  Future<void> _open(PrivateMessageNotice notice) async {
    if (!mounted) return;
    try {
      if (await widget.controller.openPrivateChatFromPush(
        notice.conversationId,
        notice.recipientId,
      )) {
        return;
      }
    } catch (_) {
      // Si no se puede recuperar el chat, informa sin mostrar datos del aviso.
    }
    if (mounted && widget.controller.currentUser?.id == notice.recipientId) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el chat. Revisa tus conversaciones.'),
        ),
      );
    }
  }

  void _showForeground(RemoteMessage message) {
    final notice = PrivateMessageNotice.fromData(message.data);
    final controller = widget.controller;
    if (notice == null ||
        controller.currentUser?.id != notice.recipientId ||
        controller.passwordRecoveryPending ||
        controller.currentSection == AppSection.practicaSimulacro ||
        controller.isViewingPrivateChat(notice.conversationId) ||
        _lastForegroundId == notice.messageId) {
      return;
    }
    _lastForegroundId = notice.messageId;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: const Text('Tienes un mensaje nuevo.'),
        action: SnackBarAction(
          label: 'Abrir chat',
          onPressed: () => unawaited(_open(notice)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_openPending);
    unawaited(_opened?.cancel());
    unawaited(_foreground?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// El permiso se pide al activar los avisos en Chats.
class PrivateMessagePushSettings extends StatefulWidget {
  const PrivateMessagePushSettings({
    super.key,
    required this.controller,
    required this.userId,
  });

  final AppController controller;
  final String userId;

  @override
  State<PrivateMessagePushSettings> createState() =>
      _PrivateMessagePushSettingsState();
}

class _PrivateMessagePushSettingsState
    extends State<PrivateMessagePushSettings> {
  final _service = PushNotificationService.instance;
  bool _available = false;
  bool _enabled = false;
  bool _busy = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final available = await _service.isAvailable;
    if (!mounted || !available) return;
    try {
      final enabled = await widget.controller.remoteGateway
          .privateMessagePushEnabled();
      if (!mounted) return;
      setState(() {
        _available = true;
        _enabled = enabled;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = true;
          _busy = false;
          _notice = 'No se pudo consultar el estado de los avisos. Vuelve a abrir Chats para reintentar.';
        });
      }
    }
  }

  Future<void> _toggle() async {
    final gateway = widget.controller.remoteGateway;
    final userId = widget.userId;
    final enable = !_enabled;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      String? id;
      if (enable) {
        final permission = await _service.requestPermission();
        if (!mounted) return;
        if (permission != AuthorizationStatus.authorized &&
            permission != AuthorizationStatus.provisional) {
          setState(
            () => _notice = 'Permite las notificaciones en los ajustes del teléfono para activarlas.',
          );
          return;
        }
        id = await _service.registerInstallation();
        if (!mounted) return;
        if (id == null) {
          setState(
            () => _notice =
                'El teléfono aún no pudo registrarse. Inténtalo de nuevo.',
          );
          return;
        }
      }
      await gateway.setPrivateMessagePush(userId, id);
      if (mounted) setState(() => _enabled = enable);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'No se pudo cambiar el estado de los avisos. Vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const Key('private_message_push_toggle'),
          onPressed: _busy ? null : _toggle,
          icon: Icon(
            _enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_outlined,
          ),
          label: Text(
            _enabled
                ? 'Desactivar avisos de mensajes'
                : 'Activar avisos de mensajes',
          ),
        ),
        if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!)),
        const SizedBox(height: 12),
      ],
    );
  }
}
