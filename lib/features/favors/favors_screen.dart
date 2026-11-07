import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Listado de favores solidarios, préstamos de herramientas, donaciones e
/// intercambio de habilidades (100% gratuitos, sin pagos).
class FavorsScreen extends StatelessWidget {
  const FavorsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final favors = controller.filteredFavors;

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
                const Text(
                  'Favores Solidarios y Ayuda Mutua',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.volunteer_activism,
                        color: AppTheme.actionGreen,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ayuda 100% gratuita y voluntaria entre vecinos. No incluye pagos ni cobros.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.actionGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Filtrar por estado:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: controller.favorStatusFilter == null,
                      onSelected: (_) =>
                          controller.updateFavorFilters(clearStatus: true),
                    ),
                    for (final st in const [
                      PublicationStatus.abierta,
                      PublicationStatus.enCoordinacion,
                      PublicationStatus.resuelta,
                    ])
                      ChoiceChip(
                        label: Text(st.label),
                        selected: controller.favorStatusFilter == st,
                        onSelected: (_) =>
                            controller.updateFavorFilters(status: st),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          Text(
            '${favors.length} solicitud(es) y ofrecimiento(s) en el barrio',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          for (final fav in favors) ...[
            _FavorCard(
              favor: fav,
              originLat: controller.activeLat,
              originLng: controller.activeLng,
              onTap: () => controller.openFavorDetail(fav),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _FavorCard extends StatelessWidget {
  const _FavorCard({
    required this.favor,
    required this.originLat,
    required this.originLng,
    required this.onTap,
  });

  final Publication favor;
  final double? originLat;
  final double? originLng;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distLabel = favor.distanceLabelFrom(lat: originLat, lng: originLng);

    return Semantics(
      button: true,
      label:
          '${favor.kind.label}: ${favor.title} por ${favor.authorAlias}, estado ${favor.status.label}. Toca para abrir y ayudar.',
      child: Material(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('card_favor_${favor.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderSoft, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    PublicationStatusBadge(status: favor.status),
                    SyncStatusBadge(status: favor.syncStatus),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  favor.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vecino(a): ${favor.authorAlias} · ${favor.sector} ($distLabel)',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.actionGreen,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  favor.description,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                const Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    Text(
                      'Abrir solicitud y ofrecer ayuda',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.actionGreen,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: AppTheme.actionGreen),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
