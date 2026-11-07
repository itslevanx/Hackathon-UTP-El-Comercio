import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Pantalla "Mis actividades, borradores y envíos pendientes":
/// - Muestra publicaciones propias y permite cambiar su estado (`abierta` ->
///   `en_coordinacion` -> `resuelta` / `cancelada`).
/// - Muestra ofertas de ayuda enviadas y recomendaciones hechas.
/// - Muestra borradores locales guardados.
/// - Muestra la cola Outbox (`outbox_operations`) de la cuenta activa con
///   reintento manual.
class MyActivitiesAndProfileScreen extends StatefulWidget {
  const MyActivitiesAndProfileScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MyActivitiesAndProfileScreen> createState() =>
      _MyActivitiesAndProfileScreenState();
}

class _MyActivitiesAndProfileScreenState
    extends State<MyActivitiesAndProfileScreen> {
  List<HelpOffer> _myOffers = const [];
  List<ServiceRecommendation> _myRecs = const [];
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadMyDetails();
  }

  Future<void> _loadMyDetails() async {
    final user = widget.controller.currentUser;
    if (user == null) return;
    final offers = await widget.controller.database.listOffersByUser(user.id);
    final recs = await widget.controller.database.listRecommendationsByUser(
      user.id,
    );
    if (mounted) {
      setState(() {
        _myOffers = offers;
        _myRecs = recs;
      });
    }
  }

  Future<void> _handleRetryAll() async {
    final summary = await widget.controller.retryOutboxSync();
    await _loadMyDetails();
    if (mounted) {
      setState(() {
        _statusMessage = summary.lastMessage.isNotEmpty
            ? summary.lastMessage
            : 'Sincronización verificada.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final user = c.currentUser;
    final myPubs = c.myPublications;
    final outbox = c.userOutbox;
    final drafts = c.userDrafts;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user != null
                      ? 'Perfil vecinal: ${user.alias}'
                      : 'Sin sesión activa',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Zona aproximada: ${c.activeNeighborhood} · ${c.activeSector}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (c.lastSyncTimestamp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Última sincronización local: ${c.lastSyncTimestamp!.toLocal().toString().substring(0, 16)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.actionGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('btn_profile_open_auth'),
                      onPressed: () => c.navigateTo(AppSection.autenticacion),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text(
                        user != null
                            ? 'Cambiar cuenta / Zona / Cerrar sesión'
                            : 'Iniciar sesión o registrarse',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('btn_profile_open_chats'),
                      onPressed: () => c.navigateTo(AppSection.chatLista),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(
                        'Mis conversaciones (${c.userConversations.length})',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.actionGreen),
              ),
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Cola Outbox de envíos pendientes de sincronizar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: outbox.isNotEmpty
                    ? AppTheme.amberWarning
                    : AppTheme.borderSoft,
                width: outbox.isNotEmpty ? 2 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      outbox.isNotEmpty
                          ? Icons.schedule_send
                          : Icons.check_circle_outline,
                      color: outbox.isNotEmpty
                          ? AppTheme.amberWarning
                          : AppTheme.actionGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cola de envíos pendientes (${outbox.length})',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Aquí aparecen los reportes o solicitudes guardados cuando no había internet. Se sincronizan sin duplicarse.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
                if (outbox.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final op in outbox)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              op.entityType == 'profile'
                                  ? 'Cambio de perfil'
                                  : op.entityType == 'conversation'
                                  ? 'Conversación'
                                  : op.entityType == 'recommendation'
                                  ? 'Recomendación'
                                  : op.entityType == 'help_offer'
                                  ? 'Oferta de ayuda'
                                  : 'Publicación',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SyncStatusBadge(status: op.syncStatus),
                            if (op.syncStatus == SyncStatus.conflicto &&
                                op.entityType.startsWith('publication'))
                              OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await widget.controller
                                        .keepDraftAndLoadServer(op.entityId);
                                    if (mounted) {
                                      setState(
                                        () => _statusMessage = 'Texto anterior guardado en borrador. Se cargó la versión del barrio.',
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => _statusMessage = 'No se pudo revisar el cambio. Recupera conexión y reintenta.',
                                      );
                                    }
                                  }
                                },
                                child: const Text(
                                  'Guardar copia y cargar versión del barrio',
                                ),
                              ),

                            if (op.lastError.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                op.lastError,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.urgentRed,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: ElevatedButton.icon(
                      key: const Key('btn_retry_all_outbox'),
                      onPressed: _handleRetryAll,
                      icon: const Icon(Icons.sync),
                      label: const Text('Reintentar envíos pendientes ahora'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Mis publicaciones y cambio de estado
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mis publicaciones y reportes (${myPubs.length})',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                if (myPubs.isEmpty)
                  const Text(
                    'Aún no has creado publicaciones con esta cuenta.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  )
                else
                  for (final pub in myPubs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderSoft),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                PublicationStatusBadge(status: pub.status),
                                SyncStatusBadge(
                                  status: pub.syncStatus,
                                  isEmergency: pub.kind.isEmergency,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              pub.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              pub.description,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (pub.status.allowedNextStatuses.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final next
                                      in pub.status.allowedNextStatuses)
                                    OutlinedButton(
                                      key: Key(
                                        'btn_my_pub_${pub.id}_to_${next.dbValue}',
                                      ),
                                      onPressed: () =>
                                          c.updatePublicationStatus(
                                            publicationId: pub.id,
                                            newStatus: next,
                                          ),
                                      child: Text('Cambiar a ${next.label}'),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Mis ofertas y recomendaciones
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mis ofertas de ayuda (${_myOffers.length}) y recomendaciones (${_myRecs.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final off in _myOffers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• Oferta enviada: "${off.note}" (${off.syncStatus.label})',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                for (final rec in _myRecs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• Recomendación: "${rec.comment}" (${rec.syncStatus.label})',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                if (drafts.isNotEmpty) ...[
                  const Divider(height: 20),
                  Text(
                    'Borradores guardados en este teléfono (${drafts.length}):',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final d in drafts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• ${d.title}: "${d.description}"',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
