import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/civic_widgets.dart';

/// Directorio barrial de oficios, servicios y productos con filtro por
/// categoría, búsqueda textual, radio espacial (PostGIS / distancia aproximada)
/// y alternancia entre Lista y Mapa accesible por cuadrantes.
class ServicesDirectoryScreen extends StatelessWidget {
  const ServicesDirectoryScreen({super.key, required this.controller});

  final AppController controller;

  static const List<MapEntry<String, String>> categories = [
    MapEntry('todos', 'Todos los oficios'),
    MapEntry('electricidad', 'Electricidad'),
    MapEntry('costura', 'Costura y ropa'),
    MapEntry('jardineria', 'Jardinería'),
    MapEntry('gasfiteria', 'Gasfitería'),
  ];

  static const List<MapEntry<double?, String>> radiusOptions = [
    MapEntry(null, 'Todo el barrio'),
    MapEntry(600, 'Hasta 600 m'),
    MapEntry(1200, 'Hasta 1.2 km'),
    MapEntry(3000, 'Hasta 3 km'),
  ];

  @override
  Widget build(BuildContext context) {
    final services = controller.filteredServices;

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Directorio de Servicios y Oficios del Barrio',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Toca una ficha para ver recomendaciones vecinales, escribir al prestador o recomendar su trabajo.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('input_search_services'),
                  onChanged: (q) =>
                      controller.updateServiceFilters(searchQuery: q),
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar por oficio, nombre o sector',
                    hintText: 'Ej. Electricista, costura, Candamo…',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Categoría:',
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
                    for (final entry in categories)
                      ChoiceChip(
                        key: Key('chip_service_cat_${entry.key}'),
                        label: Text(
                          entry.value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: controller.serviceCategoryFilter == entry.key
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                        selected: controller.serviceCategoryFilter == entry.key,
                        selectedColor: AppTheme.actionGreen,
                        backgroundColor: AppTheme.surfaceContainer,
                        onSelected: (_) => controller.updateServiceFilters(
                          category: entry.key,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Distancia máxima desde tu sector:',
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
                    for (final rad in radiusOptions)
                      ChoiceChip(
                        key: Key('chip_radius_${rad.key?.toInt() ?? 0}'),
                        label: Text(
                          rad.value,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: controller.serviceRadiusMeters == rad.key
                                ? Colors.white
                                : AppTheme.textPrimary,
                          ),
                        ),
                        selected: controller.serviceRadiusMeters == rad.key,
                        selectedColor: AppTheme.actionGreen,
                        backgroundColor: AppTheme.surfaceContainer,
                        onSelected: (_) => controller.updateServiceFilters(
                          radiusMeters: rad.key,
                          clearRadius: rad.key == null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('btn_toggle_service_map_view'),
                        onPressed: () => controller.updateServiceFilters(
                          mapQuadrantView: !controller.serviceMapQuadrantView,
                        ),
                        icon: Icon(
                          controller.serviceMapQuadrantView
                              ? Icons.view_list_outlined
                              : Icons.map_outlined,
                        ),
                        label: Text(
                          controller.serviceMapQuadrantView
                              ? 'Ver como lista detallada'
                              : 'Ver en mapa por cuadrantes',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          if (controller.serviceMapQuadrantView) ...[
            AccessibleQuadrantMapWidget(
              online:
                  controller.remoteGateway.isLiveSupabaseConnected &&
                  !controller.isOfflineMode,
              publications: services,
              originLat: controller.activeLat,
              originLng: controller.activeLng,
              onSelectPublication: controller.openServiceDetail,
            ),
            const SizedBox(height: 14),
          ],

          Text(
            '${services.length} servicio(s) disponible(s)',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          if (services.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSoft),
              ),
              child: const Text(
                'No se encontraron servicios con esos filtros en este radio. Prueba ampliar el radio a "Todo el barrio".',
                style: TextStyle(fontSize: 17, color: AppTheme.textSecondary),
              ),
            )
          else
            for (final srv in services) ...[
              _ServiceCard(
                service: srv,
                originLat: controller.activeLat,
                originLng: controller.activeLng,
                onTap: () => controller.openServiceDetail(srv),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.originLat,
    required this.originLng,
    required this.onTap,
  });

  final Publication service;
  final double originLat;
  final double originLng;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distLabel = service.distanceLabelFrom(lat: originLat, lng: originLng);

    return Semantics(
      button: true,
      label:
          'Servicio ${service.title} por ${service.authorAlias}, $distLabel, ${service.recommendationCount} opiniones vecinales. Toca para abrir ficha.',
      child: Material(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('card_service_${service.id}'),
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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PublicationStatusBadge(status: service.status),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${service.recommendationCount} opinión(es) vecinal(es)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.actionGreen,
                        ),
                      ),
                    ),
                    if (service.isDemo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Demostración Pueblo Libre',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  service.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prestador: ${service.authorAlias} · ${service.sector} ($distLabel)',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.actionGreen,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  service.description,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horario: ${service.availabilityText}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Text(
                      'Abrir ficha →',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
