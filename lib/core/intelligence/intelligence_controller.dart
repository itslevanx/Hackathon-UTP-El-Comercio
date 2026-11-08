import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_controller.dart';
import 'community_intelligence.dart';

/// Server snapshots only. Local publications never create fresh risk alerts or
/// fresh matches. Keys include user, district, request and algorithm parameters.
class IntelligenceController extends ChangeNotifier {
  IntelligenceController(
    this.app, {
    this.requestId,
    this.config = const IntelligenceConfig(),
  }) {
    config.validate();
    app.addListener(_changed);
    _scope = scope;
    _revision = _dataRevision;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
  }
  final AppController app;
  final String? requestId;
  final IntelligenceConfig config;
  String? districtOverride;
  bool districtSelectionComplete = true;
  String? get district => districtOverride ?? app.activeDistrictUbigeo;
  String get scope =>
      '${app.currentUser?.id}:$district:$requestId:$districtSelectionComplete:${config.fingerprint}';
  late String _scope;
  String _revision = '';
  String get _dataRevision =>
      '$scope:${app.isOfflineMode}:${app.publications.map((p) => '${p.id}:${p.version}:${p.updatedAt}:${p.deletedAt}').join('|')}';
  Timer? _timer;
  Timer? _debounce;
  bool _disposed = false;
  int _epoch = 0;
  bool loading = false;
  bool saved = true;
  String? notice;
  Map<String, dynamic>? snapshot;
  DateTime? get fetchedAt =>
      DateTime.tryParse(snapshot?['fetched_at'] as String? ?? '');
  bool get stale =>
      saved ||
      app.isOfflineMode ||
      DateTime.now().toUtc().isAfter(
        DateTime.tryParse(snapshot?['expires_at'] as String? ?? '') ??
            DateTime.utc(1970),
      );
  List<RiskConcentration> get risks => (snapshot?['clusters'] as List? ?? [])
      .map((e) => RiskConcentration(Map<String, dynamic>.from(e as Map)))
      .toList();
  List<HelpRecommendation> get matches => snapshot?['request'] == null
      ? []
      : CommunityMatcher(config).rank(
          Map<String, dynamic>.from(snapshot!['request'] as Map),
          (snapshot!['offers'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
  void setDistrict(String? value, {bool complete = true}) {
    districtOverride = value;
    districtSelectionComplete = complete;
    _resetScope();
    unawaited(refresh());
  }

  void _resetScope() {
    if (_scope == scope) return;
    _scope = scope;
    _epoch++;
    snapshot = null;
    loading = false;
    saved = true;
    notifyListeners();
  }

  void _changed() {
    if (_disposed) return;
    final nextRevision = _dataRevision;
    if (nextRevision == _revision) return;
    _revision = nextRevision;
    _resetScope();
    saved = true;
    notifyListeners();
    // Existing server sync polls every 30 s and notifies on publication edits,
    // deletions, reconnects and auth changes. Coalesce bursts, never map gestures.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(refresh());
    });
  }

  Future<void> refresh({bool more = false}) async {
    if (_disposed) return;
    _resetScope();
    if (loading) return;
    final owner = app.currentUser?.id;
    if (owner == null || district == null || !districtSelectionComplete) {
      snapshot = null;
      notice = 'Inicia sesión y elige un distrito para consultar.';
      notifyListeners();
      return;
    }
    final ticket = ++_epoch;
    final key = 'intelligence:v1:$scope';
    loading = true;
    notice = null;
    notifyListeners();
    try {
      final cache = await app.database.readIntelligenceCache(key);
      if (_disposed || ticket != _epoch || scope != _scope) return;
      if (snapshot == null && cache != null) {
        snapshot = cache;
        saved = true;
        notifyListeners();
      }
      if (app.isOfflineMode || !app.remoteGateway.isLiveSupabaseConnected) {
        saved = true;
        notice = 'Sin conexión: copia guardada. No confirma alertas ni disponibilidad actual.';
        return;
      }
      final value = await app.remoteGateway
          .fetchCommunityIntelligence(
            district: district!,
            radius: config.radiusMeters,
            windowMinutes: config.windowMinutes,
            minimumNeighbors: config.minimumNeighbors,
            requestId: requestId,
            afterId: more ? (snapshot?['next_cursor'] as String?) : null,
          )
          .timeout(const Duration(seconds: 12));
      if (_disposed ||
          ticket != _epoch ||
          scope != _scope ||
          app.currentUser?.id != owner) {
        return;
      }
      if (more && snapshot?['request'] != null && value['request'] != null) {
        if ((snapshot!['request'] as Map)['version'] !=
            (value['request'] as Map)['version']) {
          saved = true;
          notice = 'La solicitud cambió. Actualiza las recomendaciones.';
          return;
        }
        value['fetched_at'] = snapshot!['fetched_at'];
        value['expires_at'] = snapshot!['expires_at'];
        value['offers'] = [
          ...snapshot!['offers'] as List,
          ...value['offers'] as List,
        ];
      }
      await app.database.saveIntelligenceCache(key, value);
      if (_disposed || ticket != _epoch) return;
      snapshot = value;
      saved = false;
      if (value['complete'] != true) {
        notice = requestId == null
            ? 'Hay demasiados reportes; no se generan concentraciones con datos incompletos.'
            : 'Hay más ofertas. Carga la siguiente página para ampliar la comparación.';
      }
    } catch (error) {
      if (!_disposed && ticket == _epoch) {
        saved = true;
        if (error is AuthException ||
            (error is PostgrestException &&
                [
                  '42501',
                  'PGRST301',
                  'PGRST302',
                  'PGRST303',
                ].contains(error.code))) {
          snapshot = null;
          await app.database.saveIntelligenceCache(key, {});
        }
        notice = 'No se pudo actualizar. Reintenta cuando tengas conexión.';
      }
    } finally {
      if (!_disposed && ticket == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _debounce?.cancel();
    app.removeListener(_changed);
    super.dispose();
  }
}
