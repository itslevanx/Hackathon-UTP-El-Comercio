import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../geography/peru_location_catalog.dart';
import '../models/domain_models.dart';
import '../state/app_controller.dart';
import 'carto_basemap.dart';

/// Agrupaciones visuales de tipos ya existentes; no crea categorías de negocio.
enum MapRecordFilter { todos, servicios, favores, recursos, emergencias }

class NeighborhoodMapRecord {
  NeighborhoodMapRecord.publication(Publication value)
    : publication = value,
      resource = null;
  NeighborhoodMapRecord.resource(CommunityResource value)
    : resource = value,
      publication = null;
  final Publication? publication;
  final CommunityResource? resource;
  String get id => publication != null
      ? 'pub:${publication!.id}'
      : 'resource:${resource!.id}';
  String get title => publication?.title ?? resource!.title;
  String get description => publication?.description ?? resource!.description;
  String get category => publication?.category ?? resource!.kind;
  String? get districtUbigeo => publication?.districtUbigeo;
  String get sector => publication?.sector ?? resource!.sector;
  MapRecordFilter get group => publication == null
      ? MapRecordFilter.recursos
      : publication!.kind.isService
      ? MapRecordFilter.servicios
      : publication!.kind.isEmergency
      ? MapRecordFilter.emergencias
      : MapRecordFilter.favores;
  LatLng? get point {
    if (publication?.kind == PublicationKind.emergenciaOferta &&
        !publication!.shareResourceConsent) {
      return null;
    }
    final p = publication;
    if (p != null &&
        p.kind.isService &&
        p.shareServiceLocation &&
        approximateMapPoint(p.serviceLat, p.serviceLng) != null) {
      return LatLng(p.serviceLat!, p.serviceLng!);
    }
    return approximateMapPoint(
      publication?.approxLat ?? resource?.approxLat,
      publication?.approxLng ?? resource?.approxLng,
    );
  }
}

class ExploreMapController extends ChangeNotifier {
  ExploreMapController(this.app) {
    center = approximateMapPoint(app.activeLat, app.activeLng);
    _owner = app.currentUser?.id;
    app.addListener(_onAppChanged);
  }
  final AppController app;
  String? _owner;
  int _request = 0;
  bool _disposed = false;
  List<NeighborhoodMapRecord> _records = [];
  PeruLocationSelection zone = const PeruLocationSelection.empty();
  MapRecordFilter filter = MapRecordFilter.todos;
  String? category;
  LatLng? center;
  bool loading = false;
  bool capped = false;
  String? notice;
  bool get hasAdministrativeFilter => zone.departmentCode != null;
  bool get canQuery => !hasAdministrativeFilter || zone.districtCode != null;
  bool get canFetch =>
      app.isAuthenticated &&
      !app.isOfflineMode &&
      app.remoteGateway.isLiveSupabaseConnected &&
      canQuery;

  List<NeighborhoodMapRecord> get records => _records
      .where((r) {
        if (filter != MapRecordFilter.todos && r.group != filter) return false;
        if (category != null && r.category != category) return false;
        final prefix =
            zone.districtCode ?? zone.provinceCode ?? zone.departmentCode;
        // Los recursos históricos no tienen UBIGEO; no se deduce por nombres.
        if (prefix != null &&
            !(r.districtUbigeo?.startsWith(prefix) ?? false)) {
          return false;
        }
        return true;
      })
      .take(200)
      .toList();
  List<String> get categories =>
      (_records
          .where((r) => filter == MapRecordFilter.todos || r.group == filter)
          .map((r) => r.category)
          .followedBy(category == null ? const <String>[] : [category!])
          .toSet()
          .toList()
        ..sort());

  void _onAppChanged() {
    if (_owner != app.currentUser?.id) {
      _owner = app.currentUser?.id;
      _request++;
      _records = [];
      loading = false;
      notifyListeners();
      unawaited(loadLocal());
      return;
    }
    unawaited(loadLocal());
  }

  void setFilter(MapRecordFilter next) {
    filter = next;
    category = null;
    notifyListeners();
    unawaited(refresh());
  }

  void setCategory(String? next) {
    category = next;
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> setZone(PeruLocationSelection next) async {
    zone = app.locationCatalog.normalize(next);
    final district = app.locationCatalog.district(zone.districtCode);
    center = approximateMapPoint(district?.capitalLat, district?.capitalLng);
    if (!hasAdministrativeFilter) {
      center = approximateMapPoint(app.activeLat, app.activeLng);
    }
    notice = district != null && center == null
        ? 'Este distrito no tiene una referencia geográfica válida. Consulta la lista.'
        : null;
    notifyListeners();
    await refresh();
  }

  void centerOn(LatLng point) {
    _request++;
    loading = false;
    zone = const PeruLocationSelection.empty();
    center = approximateMapPoint(point.latitude, point.longitude);
    notifyListeners();
    unawaited(loadLocal());
  }

  Future<void> loadLocal() async {
    final ticket = _request;
    final uid = app.currentUser?.id;
    if (uid == null) {
      _records = [];
      notice = 'Inicia sesión para consultar registros vecinales.';
      if (!_disposed) notifyListeners();
      return;
    }
    final pubs = await app.database.listPublications(activeUserId: uid);
    final resources = await app.database.listCommunityResources();
    if (_disposed || ticket != _request || uid != app.currentUser?.id) return;
    bool near(double? lat, double? lng) {
      final point = approximateMapPoint(lat, lng);
      return point != null &&
          center != null &&
          AppConfig.approximateDistanceMeters(
                fromLat: center!.latitude,
                fromLng: center!.longitude,
                toLat: point.latitude,
                toLng: point.longitude,
              ) <=
              20000;
    }

    final prefix =
        zone.districtCode ?? zone.provinceCode ?? zone.departmentCode;
    final candidates = [
      for (final p in pubs)
        if ((p.status == PublicationStatus.abierta ||
                p.status == PublicationStatus.enCoordinacion) &&
            (!p.isDemo || app.remoteGateway.isTestDouble) &&
            (prefix != null
                ? (p.districtUbigeo?.startsWith(prefix) ?? false)
                : p.authorId == uid ||
                      near(p.approxLat, p.approxLng) ||
                      (app.activeDistrictUbigeo != null &&
                          p.districtUbigeo == app.activeDistrictUbigeo)))
          NeighborhoodMapRecord.publication(p),
      if (prefix == null)
        for (final r in resources)
          if ((!r.isDemo || app.remoteGateway.isTestDouble) &&
              near(r.approxLat, r.approxLng))
            NeighborhoodMapRecord.resource(r),
    ];
    capped = candidates.length > 200;
    _records = candidates;
    notifyListeners();
  }

  Future<void> refresh() async {
    final ticket = ++_request;
    await loadLocal();
    if (_disposed || ticket != _request) return;
    if (!canFetch) {
      loading = false;
      if (app.isAuthenticated && app.isOfflineMode) {
        notice = 'Sin conexión: registros guardados en este teléfono. Los envíos pendientes no están comunicados.';
      } else if (!canQuery) {
        notice = 'Filtro aplicado a la copia local. Elige un distrito para consultar el servidor.';
      }
      notifyListeners();
      return;
    }

    loading = true;
    notice = null;
    notifyListeners();
    final uid = app.currentUser!.id;
    try {
      // Recupera también las publicaciones propias anteriores a la elección de zona.
      final own = await app.remoteGateway.fetchOwnMapPublications().timeout(
        const Duration(seconds: 15),
      );
      if (_disposed || ticket != _request || uid != app.currentUser?.id) return;
      await app.database.mergeRemotePublications(own);
      await loadLocal();
      // Distrito explícito: origen nulo para que la RPC consulte todo ese código.
      // Sin filtro administrativo: radio fijo, nunca consultas al mover el mapa.
      final pubs = await app.remoteGateway
          .fetchPublicationsWithinRadius(
            originLat: hasAdministrativeFilter ? null : center?.latitude,
            originLng: hasAdministrativeFilter ? null : center?.longitude,
            radiusMeters: 20000,
            districtUbigeo: zone.districtCode ?? app.activeDistrictUbigeo,
            kind: filter == MapRecordFilter.servicios
                ? PublicationKind.servicio
                : null,
            category: category,
            maxResults: 201,
          )
          .timeout(const Duration(seconds: 15));
      if (_disposed || ticket != _request || uid != app.currentUser?.id) return;
      await app.database.mergeRemotePublications(pubs);
      await loadLocal();
      final resources = !hasAdministrativeFilter && center != null
          ? await app.remoteGateway
                .fetchMapResources(
                  originLat: center!.latitude,
                  originLng: center!.longitude,
                )
                .timeout(const Duration(seconds: 15))
          : <CommunityResource>[];
      if (_disposed || ticket != _request || uid != app.currentUser?.id) return;
      await app.database.mergeCommunitySnapshot({
        'community_resources': resources.map((r) => r.toSqlMap()).toList(),
      });
      await loadLocal();
      if (pubs.length > 200 || resources.length > 200) capped = true;
      notice = 'Registros actualizados. Solo los servicios que lo autorizan comparten su punto exacto.';
    } catch (_) {
      if (_disposed || ticket != _request) return;
      notice = 'No se pudo actualizar. Puedes consultar los registros locales y reintentar.';
    } finally {
      if (!_disposed && ticket == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    app.removeListener(_onAppChanged);
    super.dispose();
  }
}
