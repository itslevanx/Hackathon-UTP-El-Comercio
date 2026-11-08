import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geography/peru_location_catalog.dart';
import '../../core/maps/explore_map_controller.dart';
import '../../core/maps/map_location_service.dart';
import '../../core/maps/chosen_map_location.dart';
import '../../core/maps/carto_basemap.dart';
import '../../core/models/domain_models.dart';
import 'location_picker_screen.dart';
import '../../core/state/app_controller.dart';
import '../shared/peru_location_selector.dart';
import '../shared/civic_widgets.dart';
import 'neighborhood_map.dart';

class ExploreMapScreen extends StatefulWidget {
  const ExploreMapScreen({
    super.key,
    required this.controller,
    this.locationService,
  });
  final AppController controller;
  final MapLocationService? locationService;
  @override
  State<ExploreMapScreen> createState() => _ExploreMapScreenState();
}

class _ExploreMapScreenState extends State<ExploreMapScreen> {
  late final ExploreMapController _map;
  bool _filtersOpen = false;
  bool _listOnly = false;
  bool _locating = false;
  String? _locationNotice;
  LatLng? _privateLocation;
  @override
  void initState() {
    super.initState();
    _map = ExploreMapController(widget.controller);
    unawaited(_map.refresh());
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationNotice = null;
    });
    try {
      final point = await (widget.locationService ?? MapLocationService())
          .locate();
      if (!mounted) return;
      if (point == null) {
        setState(
          () => _locationNotice = 'No se obtuvo permiso o ubicación. Puedes elegir una zona sin GPS.',
        );
      } else {
        _map.centerOn(point);
        _privateLocation = point;
        setState(
          () => _locationNotice = 'Vista centrada en tu ubicación aproximada. No se guardó ni publicó. Pulsa Actualizar para consultar cerca de esta referencia.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationNotice = 'No se pudo obtener la ubicación. El mapa y la selección manual siguen disponibles.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _editLocation(NeighborhoodMapRecord record) async {
    final publication = record.publication;
    if (publication == null ||
        publication.authorId != widget.controller.currentUser?.id) {
      return;
    }
    final choice = await Navigator.push<ChosenMapLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          catalog: widget.controller.locationCatalog,
          districtUbigeo:
              publication.districtUbigeo ??
              widget.controller.activeDistrictUbigeo,
          initialPoint:
              record.point ??
              approximateMapPoint(
                widget.controller.activeLat,
                widget.controller.activeLng,
              ),
          allowExactService: publication.kind.isService,
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await widget.controller.updatePublicationLocation(publication, choice);
      _map.centerOn(choice.point);
      await _map.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ubicación guardada. Si no hay conexión, queda pendiente de sincronizar.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo actualizar la ubicación. Tu publicación se conserva.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDetails(NeighborhoodMapRecord record) async {
    final publication = record.publication;
    final resource = record.resource;
    final openPublication = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('map_record_detail'),
        scrollable: true,
        title: Text(record.title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(record.description),
            const SizedBox(height: 12),
            Text(
              '${_label(record.group)} · ${record.category.replaceAll('_', ' ')}',
            ),
            Text(
              'Zona: ${publication?.neighborhood ?? resource!.neighborhood} · ${record.sector}',
            ),
            if (publication != null) ...[
              Text('Publicado por: ${publication.authorAlias}'),
              if (publication.availabilityText.isNotEmpty)
                Text('Disponibilidad: ${publication.availabilityText}'),
              if (publication.shareServiceLocation)
                Text('Dirección de atención: ${publication.serviceAddress}'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PublicationStatusBadge(status: publication.status),
                  SyncStatusBadge(
                    status: publication.syncStatus,
                    isEmergency: publication.kind.isEmergency,
                  ),
                ],
              ),
            ],
            if (publication?.shareServiceLocation != true)
              const Text('Ubicación aproximada.'),
            if (resource != null) ...[
              Text('Fuente: ${resource.sourceLabel}'),
              if (resource.contactInfo.isNotEmpty) Text(resource.contactInfo),
            ],
          ],
        ),
        actions: [
          if (publication != null)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir publicación'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (!mounted || openPublication != true || publication == null) return;
    _openPublication(publication);
  }

  void _openPublication(Publication publication) {
    if (publication.kind.isService) {
      widget.controller.openServiceDetail(publication);
    } else {
      widget.controller.openFavorDetail(publication);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _map,
    builder: (context, _) {
      final records = _map.records;
      final visibleOnMap = records.where((r) => r.point != null).length;
      return ListView(
        key: const Key('map_results_scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Explorar mapa',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Servicios, favores, recursos y avisos del barrio. También puedes consultar todo en lista.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('map_toggle_filters'),
                onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Zona y filtros'),
              ),
              OutlinedButton.icon(
                key: const Key('map_toggle_list'),
                onPressed: () => setState(() => _listOnly = !_listOnly),
                icon: Icon(_listOnly ? Icons.map_outlined : Icons.list),
                label: Text(_listOnly ? 'Mostrar mapa' : 'Solo lista'),
              ),
            ],
          ),
          if (_filtersOpen) ...[
            const SizedBox(height: 12),
            PeruLocationSelector(
              catalog: widget.controller.locationCatalog,
              value: _map.zone,
              onChanged: (zone) => unawaited(_map.setZone(zone)),
            ),
            TextButton(
              key: const Key('map_clear_zone'),
              onPressed: () =>
                  _map.setZone(const PeruLocationSelection.empty()),
              child: const Text('Quitar filtro de zona'),
            ),
            const Text(
              'El distrito filtra por UBIGEO. Los recursos sin código administrativo solo se muestran en la vista por cercanía.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in MapRecordFilter.values)
                  ChoiceChip(
                    key: ValueKey('map_filter_${filter.name}'),
                    label: Text(_label(filter)),
                    selected: _map.filter == filter,
                    onSelected: (_) => _map.setFilter(filter),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'map_category_${_map.filter.name}_${_map.category}',
              ),
              initialValue: _map.category ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría de los registros disponibles',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Todas las categorías'),
                ),
                for (final category in _map.categories)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.replaceAll('_', ' ')),
                  ),
              ],
              onChanged: (value) =>
                  _map.setCategory(value == '' ? null : value),
            ),
          ],
          if (_map.loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(
                semanticsLabel: 'Actualizando registros',
              ),
            ),
          if (_map.notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_map.notice!, key: const Key('map_data_notice')),
            ),
          if (!widget.controller.isAuthenticated)
            TextButton(
              onPressed: () =>
                  widget.controller.navigateTo(AppSection.autenticacion),
              child: const Text('Iniciar sesión'),
            ),
          if (!_listOnly)
            NeighborhoodMap(
              records: records,
              center: _map.center,
              privateLocation: _privateLocation,
              online: !widget.controller.isOfflineMode,
              onSelect: _showDetails,
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('map_locate_me'),
                onPressed: _locating ? null : _locate,
                icon: const Icon(Icons.my_location),
                label: Text(_locating ? 'Buscando…' : 'Mi ubicación'),
              ),
              OutlinedButton.icon(
                key: const Key('map_refresh'),
                onPressed: _map.loading ? null : _map.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar registros'),
              ),
            ],
          ),
          if (_locationNotice != null)
            Semantics(liveRegion: true, child: Text(_locationNotice!)),
          const SizedBox(height: 12),
          Text(
            '${records.length} registros · $visibleOnMap con referencia en mapa',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_map.capped)
            const Text(
              'Se muestran hasta 200 registros. Usa un distrito o categoría para acotar la vista.',
            ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hay registros disponibles con estos filtros. Cambia la zona o actualiza cuando tengas conexión.',
              ),
            ),
          for (final record in records)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    key: ValueKey('map_list_${record.id}'),
                    minTileHeight: 72,
                    leading: Icon(mapRecordIcon(record.group)),
                    title: Text(record.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${record.sector} · ${_label(record.group)}'),
                        if (record.point == null)
                          const Text('Sin referencia geográfica publicable'),
                        if (record.publication != null)
                          SyncStatusBadge(
                            status: record.publication!.syncStatus,
                            isEmergency: record.publication!.kind.isEmergency,
                          ),
                      ],
                    ),
                    onTap: () {
                      final publication = record.publication;
                      if (publication == null || publication.kind.isEmergency) {
                        _showDetails(record);
                      } else {
                        _openPublication(publication);
                      }
                    },
                  ),
                  if (record.publication != null &&
                      record.publication!.authorId ==
                          widget.controller.currentUser?.id)
                    TextButton.icon(
                      key: ValueKey('map_edit_location_${record.id}'),
                      onPressed: () => _editLocation(record),
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: Text(
                        record.point == null
                            ? 'Ubicar esta publicación en el mapa'
                            : 'Cambiar ubicación de mi publicación',
                      ),
                    ),
                  if (record.point != null)
                    TextButton.icon(
                      key: ValueKey('map_show_point_${record.id}'),
                      onPressed: () => _map.centerOn(record.point!),
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Ver este punto en el mapa'),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
  String _label(MapRecordFilter filter) => switch (filter) {
    MapRecordFilter.todos => 'Todos',
    MapRecordFilter.servicios => 'Servicios',
    MapRecordFilter.favores => 'Favores',
    MapRecordFilter.recursos => 'Recursos',
    MapRecordFilter.emergencias => 'Emergencias',
  };
}
