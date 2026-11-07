import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Centro comunitario de emergencias barriales:
/// - Acceso directo a reportar necesidad u ofrecer recurso (con decisión explícita).
/// - Mapa accesible por cuadrantes y lista de reportes activos.
/// - Puntos públicos de referencia, recursos comunitarios y brigadas solidarias.
/// - Directorio oficial de emergencias peruanas (`105`, `116`, `106`, `115`).
class EmergencyHubScreen extends StatelessWidget {
  const EmergencyHubScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final emergencyPubs = controller.emergencyPublications;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OfficialEmergencyChannelsCard(),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 58),
                  child: ElevatedButton.icon(
                    key: const Key('btn_hub_reportar_emergencia'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.urgentRed,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => controller.openQuickPublish(
                      presetKind: PublicationKind.emergenciaSolicitud,
                      lockTypeForTwoClickFlow: true,
                    ),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Reportar necesidad'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 58),
                  child: ElevatedButton.icon(
                    key: const Key('btn_hub_ofrecer_recurso'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.actionGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => controller.openQuickPublish(
                      presetKind: PublicationKind.emergenciaOferta,
                      lockTypeForTwoClickFlow: false,
                    ),
                    icon: const Icon(Icons.medical_services_outlined),
                    label: const Text('Compartir recurso'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text(
            'Reportes comunitarios de emergencia en tu sector',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          for (final em in emergencyPubs) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => controller.openFavorDetail(em),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          PublicationStatusBadge(status: em.status),
                          SyncStatusBadge(
                            status: em.syncStatus,
                            isEmergency: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        em.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${em.authorAlias} · ${em.sector} (Zona aproximada)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.urgentRed,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        em.description,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          AccessibleQuadrantMapWidget(
            online:
                controller.remoteGateway.isLiveSupabaseConnected &&
                !controller.isOfflineMode,
            publications: emergencyPubs,
            originLat: controller.activeLat,
            originLng: controller.activeLng,
            onSelectPublication: controller.openFavorDetail,
          ),

          const SizedBox(height: 16),
          const Text(
            'Brigadas y grupos solidarios del barrio',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final grp in controller.supportGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
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
                      grp.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      grp.description,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${grp.coordinatorLabel} · ${grp.channelNote}',
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
        ],
      ),
    );
  }
}
