import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../geography/peru_location_catalog.dart';
import '../maps/chosen_map_location.dart';
import '../maps/carto_basemap.dart';
import '../models/entity_id.dart';
import '../database/local_sqlite_database.dart';
import '../models/domain_models.dart';
import '../sync/outbox_sync_service.dart';
import '../sync/supabase_remote_gateway.dart';

/// Intención conservada cuando un vecino sin sesión activa intenta realizar una
/// acción que requiere autenticación, para retomarla inmediatamente al ingresar.
class PendingAuthIntent {
  const PendingAuthIntent({
    required this.description,
    required this.targetRoute,
    this.publicationId,
    this.presetKind,
    this.lockType = false,
  });

  final String description;
  final String targetRoute;
  final String? publicationId;
  final PublicationKind? presetKind;
  final bool lockType;
}

/// Rutas principales de primer nivel accesibles desde Inicio en 1 clic.
enum AppSection {
  inicio,
  publicarRapido,
  servicios,
  detalleServicio,
  favores,
  detalleFavor,
  emergencias,
  explorarMapa,
  chatLista,
  chatConversacion,
  misActividades,
  autenticacion,
  practicaSimulacro,
}

/// Controlador central de estado de la aplicación comunitaria NEXO.
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  Timer? _syncTimer;
  StreamSubscription<void>? _authSubscription;
  StreamSubscription<void>? _recoverySubscription;
  bool _passwordRecoveryPending = false;
  bool get passwordRecoveryPending => _passwordRecoveryPending;
  bool _authActionInProgress = false;
  bool _restoringAuthSession = false;
  int _authEpoch = 0;
  bool _refreshingRemote = false;
  bool _disposed = false;
  AppController({
    required this.database,
    required this.remoteGateway,
    required this.outboxSyncService,
  });

  final LocalSqliteDatabase database;
  final SupabaseRemoteGateway remoteGateway;
  final OutboxSyncService outboxSyncService;

  late final PeruLocationCatalog locationCatalog;
  String? _selectedManualUbigeo;
  bool _selectedManualUsesGps = false;
  bool get activeUsesGps =>
      _currentUser?.useGpsApprox ?? _selectedManualUsesGps;
  String? get activeDistrictUbigeo => _currentUser != null
      ? _currentUser!.districtUbigeo
      : _selectedManualUbigeo;

  String get activeAdministrativeLocationLabel {
    final district = locationCatalog.district(activeDistrictUbigeo);
    if (district == null) return activeNeighborhood;
    return '${district.name}, ${locationCatalog.entry(district.provinceCode)!.name}, ${locationCatalog.entry(district.departmentCode)!.name}';
  }

  bool _initialized = false;
  bool get initialized => _initialized;

  UserProfile? _currentUser;
  UserProfile? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  String get activeNeighborhood =>
      _currentUser?.neighborhood ?? _selectedManualNeighborhood;
  String get activeSector => _currentUser?.sector ?? _selectedManualSector;
  double? get activeLat =>
      _currentUser != null ? _currentUser!.approxLat : _selectedManualLat;
  double? get activeLng =>
      _currentUser != null ? _currentUser!.approxLng : _selectedManualLng;

  String _selectedManualNeighborhood = AppConfig.defaultNeighborhood;
  String _selectedManualSector = AppConfig.defaultSector;
  double? _selectedManualLat = AppConfig.defaultLat;
  double? _selectedManualLng = AppConfig.defaultLng;

  AppSection _currentSection = AppSection.inicio;
  AppSection get currentSection => _currentSection;

  final List<AppSection> _navigationStack = <AppSection>[AppSection.inicio];

  /// Estado del flujo de publicación rápida (2 clics para emergencia / pedir ayuda,
  /// 3 clics para publicar servicio o favor general).
  PublicationKind _publishPresetKind = PublicationKind.favorSolicitud;
  PublicationKind get publishPresetKind => _publishPresetKind;

  bool _publishTypeLocked = false;
  bool get publishTypeLocked => _publishTypeLocked;

  Publication? _lastSubmittedPublication;
  Publication? get lastSubmittedPublication => _lastSubmittedPublication;

  /// Filtros del directorio de servicios
  String _serviceSearchQuery = '';
  String get serviceSearchQuery => _serviceSearchQuery;

  String _serviceCategoryFilter = 'todos';
  String get serviceCategoryFilter => _serviceCategoryFilter;

  double? _serviceRadiusMeters;
  double? get serviceRadiusMeters => _serviceRadiusMeters;

  bool _serviceMapQuadrantView = false;
  bool get serviceMapQuadrantView => _serviceMapQuadrantView;

  /// Filtros de favores solidarios
  String _favorCategoryFilter = 'todos';
  String get favorCategoryFilter => _favorCategoryFilter;

  PublicationStatus? _favorStatusFilter;
  PublicationStatus? get favorStatusFilter => _favorStatusFilter;

  /// Selección de detalle y conversación
  Publication? _selectedPublication;
  Publication? get selectedPublication => _selectedPublication;

  ConversationThread? _selectedConversation;
  ConversationThread? get selectedConversation => _selectedConversation;

  PendingAuthIntent? _pendingAuthIntent;
  PendingAuthIntent? get pendingAuthIntent => _pendingAuthIntent;

  bool _showOnboardingTutorial = false;
  bool get showOnboardingTutorial => _showOnboardingTutorial;

  String? _statusBannerMessage;
  String? get statusBannerMessage => _statusBannerMessage;

  List<Publication> _publications = const [];
  List<Publication> get publications => _publications;

  List<CommunityResource> _communityResources = const [];
  List<CommunityResource> get communityResources => _communityResources;

  List<SupportGroup> _supportGroups = const [];
  List<SupportGroup> get supportGroups => _supportGroups;

  List<OutboxOperation> _userOutbox = const [];
  List<OutboxOperation> get userOutbox => _userOutbox;

  List<FormDraft> _userDrafts = const [];
  List<FormDraft> get userDrafts => _userDrafts;

  List<ConversationThread> _userConversations = const [];
  List<ConversationThread> get userConversations => _userConversations;

  DateTime? _lastSyncTimestamp;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;

  bool get isOfflineMode =>
      remoteGateway.simulateNetworkOffline ||
      (!remoteGateway.isLiveSupabaseConnected && !remoteGateway.isTestDouble);

  /// Inicializa SQLite, semilla comunitaria de Pueblo Libre y sesión activa.
  Future<void> initialize({bool startWithActiveSession = true}) async {
    locationCatalog = await PeruLocationCatalog.load();
    await database.initAndSeedDemoData(seedDemo: remoteGateway.isTestDouble);
    final manual = await database.readManualLocation();
    if (manual != null) {
      _selectedManualUbigeo = manual['district_ubigeo'] as String?;
      _selectedManualUsesGps = manual['use_gps_approx'] == 1;
      _selectedManualNeighborhood = manual['neighborhood'] as String;
      _selectedManualSector = manual['sector'] as String;
      _selectedManualLat = (manual['approx_lat'] as num?)?.toDouble();
      _selectedManualLng = (manual['approx_lng'] as num?)?.toDouble();
    }

    if (startWithActiveSession) {
      final sessionProfile = await remoteGateway.getCurrentSessionProfile();
      if (sessionProfile != null) {
        _currentUser = await _preferPendingLocalProfile(sessionProfile);
      } else if (remoteGateway.isTestDouble) {
        // Sesión vecinal por defecto para permitir verificación inmediata del
        // presupuesto de <= 3 clics desde Inicio (puede cerrarse o cambiarse).
        final defaultProfile = await remoteGateway.signInAccount(
          email: 'maria@pueblolibre.pe',
          password: 'vecinos-pueblo-libre',
        );
        _currentUser = defaultProfile;
      }
      if (_currentUser != null) {
        await database.saveUserProfile(_currentUser!, queueSync: false);
      }
    }

    await refreshAllLocalData();
    _initialized = true;
    _authSubscription = remoteGateway.signedInSessionChanges.listen(
      (_) {
        if (!_authActionInProgress) unawaited(_restoreSessionFromLink());
      },
      onError: (Object error) {
        if (_disposed) return;
        _statusBannerMessage =
            'No se pudo completar la confirmación. Vuelve a iniciar sesión.';
        notifyListeners();
      },
    );
    _recoverySubscription = remoteGateway.passwordRecoveryChanges.listen(
      (_) {
        if (_disposed || !remoteGateway.hasPasswordRecoverySession) return;
        _authEpoch++;
        _passwordRecoveryPending = true;
        _currentUser = null;
        _selectedConversation = null;
        _selectedPublication = null;
        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed) return;
        _statusBannerMessage = 'El enlace no es válido o venció. Solicita otro correo de recuperación.';
        notifyListeners();
      },
    );
    if (remoteGateway.isLiveSupabaseConnected && !remoteGateway.isTestDouble) {
      if (startWithActiveSession && _currentUser == null) {
        unawaited(_restoreSessionFromLink());
      }
      WidgetsBinding.instance.addObserver(this);
      _syncTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => refreshFromServer(),
      );
      unawaited(refreshFromServer());
    }
    notifyListeners();
  }

  Future<void> refreshFromServer() async {
    if (_refreshingRemote ||
        _disposed ||
        _currentUser == null ||
        !remoteGateway.isLiveSupabaseConnected ||
        remoteGateway.simulateNetworkOffline) {
      return;
    }
    _refreshingRemote = true;
    final uid = _currentUser!.id;
    try {
      await outboxSyncService.syncPendingForUser(uid);
      final publications = await remoteGateway.fetchPublicationsWithinRadius(
        originLat: activeLat,
        originLng: activeLng,
        districtUbigeo: activeDistrictUbigeo,
        radiusMeters: 20000,
      );
      final snapshot = await remoteGateway.fetchCommunitySnapshot();
      if (_disposed || _currentUser?.id != uid) return;
      await database.mergeRemotePublications(publications);
      await database.mergeCommunitySnapshot(snapshot);
      await refreshAllLocalData();
    } catch (_) {
      if (!_disposed && _currentUser?.id == uid) {
        _statusBannerMessage = 'No se pudo actualizar el barrio. Consulta la copia guardada; los envíos pendientes aún NO están comunicados.';
        notifyListeners();
      }
    } finally {
      _refreshingRemote = false;
    }
  }

  Future<UserProfile> _preferPendingLocalProfile(UserProfile remote) async {
    final local = await database.getUserProfile(remote.id);
    if (local == null) return remote;
    final pending = await database.listOutboxForUser(remote.id);
    return remoteGateway.lastProfileFetchWasOffline ||
            pending.any(
              (op) =>
                  op.entityType == 'profile' &&
                  op.syncStatus != SyncStatus.confirmado,
            )
        ? local
        : remote;
  }

  Future<void> _restoreSessionFromLink() async {
    if (_disposed ||
        _restoringAuthSession ||
        _authActionInProgress ||
        _passwordRecoveryPending) {
      return;
    }
    _restoringAuthSession = true;
    final epoch = _authEpoch;
    try {
      final remoteProfile = await remoteGateway.getCurrentSessionProfile();
      if (remoteProfile == null) return;
      final profile = await _preferPendingLocalProfile(remoteProfile);
      if (_disposed ||
          epoch != _authEpoch ||
          _authActionInProgress ||
          _currentUser?.id == profile.id) {
        return;
      }
      final previousId = _currentUser?.id;
      if (previousId != null) {
        await database.clearPrivateCacheOnSignOut(previousId);
      }
      if (_disposed || epoch != _authEpoch) return;
      _selectedConversation = null;
      _currentUser = profile;
      await database.saveUserProfile(profile, queueSync: false);
      if (_disposed || epoch != _authEpoch) return;
      await refreshAllLocalData();
      if (_disposed || epoch != _authEpoch) return;
      _resumePendingIntentOrGoHome();
      unawaited(refreshFromServer());
    } catch (_) {
      if (!_disposed) {
        _statusBannerMessage =
            'Correo confirmado. Inicia sesión para entrar al barrio.';
        notifyListeners();
      }
    } finally {
      _restoringAuthSession = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshFromServer());
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_recoverySubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Recarga todas las listas desde SQLite respetando el aislamiento por usuario.
  Future<void> refreshAllLocalData() async {
    final activeId = _currentUser?.id ?? 'anonymous';
    final allPublications = await database.listPublications(
      activeUserId: activeId,
    );
    _publications = allPublications.where((publication) {
      if (publication.authorId == _currentUser?.id) return true;
      final distance = publication.distanceFrom(lat: activeLat, lng: activeLng);
      return (distance != null && distance <= 20000) ||
          (activeDistrictUbigeo != null &&
              publication.districtUbigeo == activeDistrictUbigeo);
    }).toList();
    _communityResources = await database.listCommunityResources(
      neighborhood: activeNeighborhood,
    );
    _supportGroups = await database.listSupportGroups(
      neighborhood: activeNeighborhood,
    );
    _lastSyncTimestamp = await database.getLastSyncTimestamp();

    if (_currentUser != null) {
      _userOutbox = await database.listOutboxForUser(_currentUser!.id);
      _userDrafts = await database.listDraftsForUser(_currentUser!.id);
      _userConversations = await database.listConversationsForUser(
        _currentUser!.id,
      );
    } else {
      _userOutbox = const [];
      _userDrafts = const [];
      _userConversations = const [];
    }

    if (_selectedPublication != null) {
      final updated = _publications
          .where((p) => p.id == _selectedPublication!.id)
          .toList();
      if (updated.isNotEmpty) {
        _selectedPublication = updated.first;
      }
    }

    notifyListeners();
  }

  /// Activa o desactiva el modo sin conexión para pruebas o uso real sin red.
  Future<void> setOfflineMode(bool offline) async {
    remoteGateway.simulateNetworkOffline = offline;
    if (!offline && _currentUser != null) {
      final summary = await outboxSyncService.syncPendingForUser(
        _currentUser!.id,
      );
      if (summary.confirmedCount > 0) {
        _statusBannerMessage =
            'Conexión restablecida: ${summary.confirmedCount} envío(s) confirmado(s) con el barrio.';
      }
    } else if (offline) {
      _statusBannerMessage = 'Modo sin conexión activo: puedes consultar datos guardados y crear solicitudes en cola local.';
    }
    await refreshAllLocalData();
  }

  void clearStatusBanner() {
    _statusBannerMessage = null;
    notifyListeners();
  }

  void toggleOnboardingTutorial(bool visible) {
    _showOnboardingTutorial = visible;
    notifyListeners();
  }

  /// Navegación directa sin pasos redundantes.
  void navigateTo(AppSection section) {
    _lastSubmittedPublication = null;
    if (_currentSection != section) {
      _navigationStack.add(section);
      _currentSection = section;
    }
    notifyListeners();
  }

  void goHome() {
    _lastSubmittedPublication = null;
    _navigationStack
      ..clear()
      ..add(AppSection.inicio);
    _currentSection = AppSection.inicio;
    notifyListeners();
  }

  void goBack() {
    _lastSubmittedPublication = null;
    if (_navigationStack.length > 1) {
      _navigationStack.removeLast();
      _currentSection = _navigationStack.last;
    } else {
      _currentSection = AppSection.inicio;
    }
    notifyListeners();
  }

  /// Clic 1 desde Inicio:
  /// - `Reportar emergencia` -> tipo `emergenciaSolicitud` y prioridad `emergencia` predefinidos (2 clics total).
  /// - `Necesito ayuda` -> tipo `favorSolicitud` y prioridad `normal` predefinidos (2 clics total).
  /// - `Publicar servicio o favor` -> permite elegir tipo en clic 2 y enviar en clic 3 (3 clics total).
  void openQuickPublish({
    required PublicationKind presetKind,
    required bool lockTypeForTwoClickFlow,
  }) {
    _lastSubmittedPublication = null;
    _publishPresetKind = presetKind;
    _publishTypeLocked = lockTypeForTwoClickFlow;

    if (!isAuthenticated) {
      _pendingAuthIntent = PendingAuthIntent(
        description: presetKind.isEmergency
            ? 'Reportar emergencia vecinal'
            : 'Publicar en mi barrio',
        targetRoute: 'publicar',
        presetKind: presetKind,
        lockType: lockTypeForTwoClickFlow,
      );
      navigateTo(AppSection.autenticacion);
      return;
    }

    navigateTo(AppSection.publicarRapido);
  }

  void setPublishPresetKind(PublicationKind kind) {
    _publishPresetKind = kind;
    notifyListeners();
  }

  /// Clic 2 (en flujos de emergencia/ayuda) o Clic 3 (en flujo de servicio/favor):
  /// Guarda en SQLite y cola Outbox dentro de la misma transacción e intenta
  /// sincronizar si hay conexión.
  Future<Publication> submitPublication({
    required PublicationKind kind,
    required String category,
    required String title,
    required String description,
    String availabilityText = '',
    bool shareResourceConsent = false,
    String? customClientMutationId,
    ChosenMapLocation? location,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para publicar en tu barrio.');
    }
    if (title.trim().isEmpty) {
      throw StateError('Escribe un título breve y claro.');
    }
    if (description.trim().isEmpty) {
      throw StateError('Describe brevemente qué necesitas o qué ofreces.');
    }

    if (location != null) _validatePublicationLocation(location, kind);
    final now = DateTime.now().toUtc();
    final mutationId = customClientMutationId ?? EntityId.create();
    final pubId = EntityId.create();

    final priority = kind.isEmergency
        ? PublicationPriority.emergencia
        : PublicationPriority.normal;

    final draftPub = Publication(
      id: pubId,
      clientMutationId: mutationId,
      ownerUserId: user.id,
      authorId: user.id,
      authorAlias: user.alias,
      kind: kind,
      category: category,
      title: title.trim(),
      description: description.trim(),
      neighborhood: location == null
          ? user.neighborhood
          : locationCatalog.district(location.districtUbigeo)!.name,
      sector: user.sector,
      districtUbigeo: location?.districtUbigeo ?? user.districtUbigeo,
      availabilityText: availabilityText.trim().isEmpty
          ? 'Horario flexible previa coordinación'
          : availabilityText.trim(),
      priority: priority,
      status: PublicationStatus.abierta,
      approxLat: location?.publicLat ?? user.approxLat,
      approxLng: location?.publicLng ?? user.approxLng,
      shareResourceConsent: shareResourceConsent,
      shareServiceLocation: location?.shareExactService ?? false,
      serviceLat: location?.serviceLat,
      serviceLng: location?.serviceLng,
      serviceAddress: location?.shareExactService == true
          ? location!.address
          : '',
      syncStatus: SyncStatus.pendiente,
      createdAt: now,
      updatedAt: now,
    );

    final savedLocal = await database.createOrUpdatePublicationTransactional(
      draftPub,
    );

    // Intento inmediato de sincronización si hay red disponible
    await outboxSyncService.syncPendingForUser(
      user.id,
      onlyOperationId: savedLocal.clientMutationId,
    );

    await refreshAllLocalData();
    final refreshed = _publications
        .where((p) => p.id == savedLocal.id)
        .toList();
    final effectivePub = refreshed.isNotEmpty ? refreshed.first : savedLocal;
    _lastSubmittedPublication = effectivePub;
    notifyListeners();
    return effectivePub;
  }

  /// Abre el detalle de un servicio (Clic 2 desde Buscar servicios).
  void openServiceDetail(Publication service) {
    _selectedPublication = service;
    navigateTo(AppSection.detalleServicio);
  }

  /// Abre el detalle de un favor o emergencia (Clic 2 desde Ver favores y ayudar).
  void openFavorDetail(Publication favor) {
    _selectedPublication = favor;
    navigateTo(AppSection.detalleFavor);
  }

  /// Clic 3 en `Buscar servicios` -> abrir ficha -> `He usado este servicio y lo recomiendo`.
  Future<ServiceRecommendation> recommendService({
    required Publication service,
    String comment = 'Buen trato vecinal y cumplimiento puntual.',
    bool allowUpdateExisting = false,
  }) async {
    final user = _currentUser;
    if (user == null) {
      _pendingAuthIntent = PendingAuthIntent(
        description: 'Recomendar servicio de ${service.authorAlias}',
        targetRoute: 'detalle_servicio',
        publicationId: service.id,
      );
      navigateTo(AppSection.autenticacion);
      throw StateError('Inicia sesión para registrar tu recomendación.');
    }

    final rec = await database.submitOrUpdateRecommendation(
      id: EntityId.forContext('recommendation:${service.id}:${user.id}'),
      clientMutationId: EntityId.forContext(
        'recommendation:${service.id}:${user.id}',
      ),
      publicationId: service.id,
      userId: user.id,
      userAlias: user.alias,
      comment: comment,
      allowUpdateExisting: allowUpdateExisting,
    );

    await outboxSyncService.syncPendingForUser(
      user.id,
      onlyOperationId: rec.clientMutationId,
    );
    await refreshAllLocalData();
    _statusBannerMessage =
        'Tu opinión vecinal quedó registrada en la ficha del servicio.';
    notifyListeners();
    return rec;
  }

  Future<void> withdrawServiceRecommendation(Publication service) async {
    final user = _currentUser;
    if (user == null) return;
    await database.withdrawRecommendation(
      publicationId: service.id,
      userId: user.id,
    );
    await outboxSyncService.syncPendingForUser(user.id);
    await refreshAllLocalData();
    _statusBannerMessage = 'Retiraste tu recomendación de este servicio.';
    notifyListeners();
  }

  /// Clic 3 en `Buscar servicios` -> abrir ficha -> escribir mensaje y `Enviar solicitud de contacto`.
  Future<ConversationThread> requestContactWithProvider({
    required Publication publication,
    required String initialMessage,
  }) async {
    final user = _currentUser;
    if (user == null) {
      _pendingAuthIntent = PendingAuthIntent(
        description: 'Contactar a ${publication.authorAlias}',
        targetRoute: 'detalle_servicio',
        publicationId: publication.id,
      );
      navigateTo(AppSection.autenticacion);
      throw StateError('Inicia sesión para contactar a este vecino.');
    }

    final cleanMessage = initialMessage.trim().isEmpty
        ? 'Hola ${publication.authorAlias}, vi tu publicación en el barrio y quisiera coordinar.'
        : initialMessage.trim();

    final thread = await database.openOrGetConversation(
      id: EntityId.forContext('conversation:${publication.id}:${user.id}'),
      clientMutationId: EntityId.forContext(
        'conversation:${publication.id}:${user.id}',
      ),
      publication: publication,
      participantId: user.id,
      participantAlias: user.alias,
    );

    await database.saveDraft(
      FormDraft(
        draftKey: 'chat_${thread.id}',
        ownerUserId: user.id,
        kind: publication.kind,
        title: 'Mensaje de contacto',
        description: cleanMessage,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await outboxSyncService.syncPendingForUser(
      user.id,
      onlyOperationId: thread.clientMutationId,
    );

    // Regla del encargo: los mensajes de chat requieren conexión activa;
    // si está offline, no se fingen enviados y se conserva el texto como borrador.
    if (remoteGateway.simulateNetworkOffline) {
      await database.saveDraft(
        FormDraft(
          draftKey: 'chat_${thread.id}',
          ownerUserId: user.id,
          kind: publication.kind,
          title: 'Mensaje para ${publication.authorAlias}',
          description: cleanMessage,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      _selectedConversation = thread;
      await refreshAllLocalData();
      _statusBannerMessage = 'Sin conexión: la conversación quedó preparada y tu mensaje se guardó como borrador para enviarlo al reconectar.';
      navigateTo(AppSection.chatConversacion);
      return thread;
    }

    final msgId = EntityId.create();
    final msgMutationId = EntityId.create();

    await remoteGateway.sendRealtimeMessage(
      id: msgId,
      clientMutationId: msgMutationId,
      conversationId: thread.id,
      senderId: user.id,
      senderAlias: user.alias,
      body: cleanMessage,
    );

    await database.recordOnlineMessage(
      id: msgId,
      clientMutationId: msgMutationId,
      conversationId: thread.id,
      senderId: user.id,
      senderAlias: user.alias,
      body: cleanMessage,
      syncStatus: SyncStatus.confirmado,
    );

    await database.deleteDraft(
      ownerUserId: user.id,
      draftKey: 'chat_${thread.id}',
    );
    _selectedConversation = thread;
    await refreshAllLocalData();
    _statusBannerMessage =
        'Solicitud de contacto enviada a ${publication.authorAlias}.';
    navigateTo(AppSection.chatConversacion);
    return thread;
  }

  /// Clic 3 en `Ver favores y ayudar` -> abrir solicitud -> nota opcional y `Enviar oferta de ayuda`.
  Future<HelpOffer> submitOfferToHelp({
    required Publication publication,
    required String note,
    String resourceShared = '',
    bool explicitShareConsent = false,
  }) async {
    final user = _currentUser;
    if (user == null) {
      _pendingAuthIntent = PendingAuthIntent(
        description: 'Ofrecer ayuda a ${publication.authorAlias}',
        targetRoute: 'detalle_favor',
        publicationId: publication.id,
      );
      navigateTo(AppSection.autenticacion);
      throw StateError('Inicia sesión para ofrecer tu ayuda.');
    }

    final cleanNote = note.trim().isEmpty
        ? 'Hola ${publication.authorAlias}, soy vecino de ${user.sector} y puedo ayudarte gratuitamente.'
        : note.trim();

    final offer = await database.submitHelpOffer(
      id: EntityId.forContext('offer:${publication.id}:${user.id}'),
      clientMutationId: EntityId.forContext(
        'offer:${publication.id}:${user.id}',
      ),
      publicationId: publication.id,
      helperId: user.id,
      helperAlias: user.alias,
      note: cleanNote,
      resourceShared: resourceShared,
      explicitShareConsent: explicitShareConsent,
    );

    await outboxSyncService.syncPendingForUser(
      user.id,
      onlyOperationId: offer.clientMutationId,
    );

    await refreshAllLocalData();
    _statusBannerMessage = offer.syncStatus.isConfirmed
        ? 'Oferta solidaria enviada y confirmada.'
        : 'Sin conexión: tu oferta de ayuda se guardó en este teléfono (Pendiente de sincronizar).';
    notifyListeners();
    return offer;
  }

  /// Cambia el estado de una publicación propia (`abierta` -> `en_coordinacion` -> `resuelta` / `cancelada`).
  Future<Publication> updatePublicationStatus({
    required String publicationId,
    required PublicationStatus newStatus,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para gestionar tus publicaciones.');
    }
    final updated = await database.transitionPublicationStatus(
      publicationId: publicationId,
      actingUserId: user.id,
      newStatus: newStatus,
    );
    await outboxSyncService.syncPendingForUser(user.id);
    await refreshAllLocalData();
    _statusBannerMessage = 'Estado actualizado a "${newStatus.label}".';
    notifyListeners();
    return updated;
  }

  /// Envía un mensaje dentro de una conversación privada existente.
  /// Si está offline, bloquea el envío ficticio, informa que requiere conexión
  /// y conserva el texto como borrador local.
  Future<void> sendChatMessageInThread({
    required ConversationThread thread,
    required String text,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para enviar mensajes.');
    }
    final clean = text.trim();
    if (clean.isEmpty) {
      throw StateError('Escribe un mensaje antes de enviar.');
    }

    if (remoteGateway.simulateNetworkOffline) {
      await database.saveDraft(
        FormDraft(
          draftKey: 'chat_${thread.id}',
          ownerUserId: user.id,
          kind: PublicationKind.servicio,
          title: 'Borrador de chat con ${thread.publicationAuthorAlias}',
          description: clean,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await refreshAllLocalData();
      throw StateError(
        'Los mensajes de chat requieren conexión activa y no se envían sin internet. Conservamos tu texto como borrador.',
      );
    }

    await database.saveDraft(
      FormDraft(
        draftKey: 'chat_${thread.id}',
        ownerUserId: user.id,
        kind: PublicationKind.servicio,
        title: 'Mensaje',
        description: clean,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    final msgId = EntityId.create();
    final mutId = EntityId.create();

    await remoteGateway.sendRealtimeMessage(
      id: msgId,
      clientMutationId: mutId,
      conversationId: thread.id,
      senderId: user.id,
      senderAlias: user.alias,
      body: clean,
    );

    await database.recordOnlineMessage(
      id: msgId,
      clientMutationId: mutId,
      conversationId: thread.id,
      senderId: user.id,
      senderAlias: user.alias,
      body: clean,
      syncStatus: SyncStatus.confirmado,
    );

    await database.deleteDraft(
      ownerUserId: user.id,
      draftKey: 'chat_${thread.id}',
    );
    await refreshAllLocalData();
  }

  void openConversation(ConversationThread thread) {
    _selectedConversation = thread;
    navigateTo(AppSection.chatConversacion);
  }

  void _validatePublicationLocation(
    ChosenMapLocation location,
    PublicationKind kind,
  ) {
    if (locationCatalog.district(location.districtUbigeo) == null ||
        approximateMapPoint(
              location.point.latitude,
              location.point.longitude,
            ) ==
            null) {
      throw StateError('Selecciona un distrito y punto válidos.');
    }
    if (location.shareExactService && !kind.isService) {
      throw StateError('Solo un servicio puede compartir un punto exacto.');
    }
    if (location.address.length > 300) {
      throw StateError('La dirección debe tener como máximo 300 caracteres.');
    }
  }

  Future<void> updatePublicationLocation(
    Publication publication,
    ChosenMapLocation location,
  ) async {
    final uid = _currentUser?.id;
    if (uid == null || publication.authorId != uid) {
      throw StateError('Solo el autor puede ubicar su publicación.');
    }
    _validatePublicationLocation(location, publication.kind);
    await database.updatePublicationLocation(
      publicationId: publication.id,
      actingUserId: uid,
      location: location.toMap(),
    );
    await refreshAllLocalData();
    if (!isOfflineMode) await outboxSyncService.syncPendingForUser(uid);
    if (_currentUser?.id == uid) await refreshAllLocalData();
  }

  /// Actualiza filtros del directorio de servicios
  void updateServiceFilters({
    String? searchQuery,
    String? category,
    double? radiusMeters,
    bool clearRadius = false,
    bool? mapQuadrantView,
  }) {
    if (searchQuery != null) _serviceSearchQuery = searchQuery;
    if (category != null) _serviceCategoryFilter = category;
    if (clearRadius) {
      _serviceRadiusMeters = null;
    } else if (radiusMeters != null) {
      _serviceRadiusMeters = radiusMeters;
    }
    if (mapQuadrantView != null) _serviceMapQuadrantView = mapQuadrantView;
    notifyListeners();
  }

  List<Publication> get filteredServices {
    return _publications.where((p) {
      if (!p.kind.isService) return false;
      if (_serviceCategoryFilter != 'todos' &&
          p.category != _serviceCategoryFilter) {
        return false;
      }
      if (_serviceSearchQuery.trim().isNotEmpty) {
        final q = _serviceSearchQuery.trim().toLowerCase();
        final match =
            p.title.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q) ||
            p.authorAlias.toLowerCase().contains(q) ||
            p.sector.toLowerCase().contains(q);
        if (!match) return false;
      }
      if (_serviceRadiusMeters != null && _serviceRadiusMeters! > 0) {
        final dist = p.distanceFrom(lat: activeLat, lng: activeLng);
        if (dist != null && dist > _serviceRadiusMeters!) return false;
        if (dist == null &&
            (activeDistrictUbigeo == null ||
                p.districtUbigeo != activeDistrictUbigeo)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void updateFavorFilters({
    String? category,
    PublicationStatus? status,
    bool clearStatus = false,
  }) {
    if (category != null) _favorCategoryFilter = category;
    if (clearStatus) {
      _favorStatusFilter = null;
    } else if (status != null) {
      _favorStatusFilter = status;
    }
    notifyListeners();
  }

  List<Publication> get filteredFavors {
    return _publications.where((p) {
      if (!p.kind.isSolidarityFavor) return false;
      if (_favorCategoryFilter != 'todos' &&
          p.category != _favorCategoryFilter) {
        return false;
      }
      if (_favorStatusFilter != null && p.status != _favorStatusFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Publication> get emergencyPublications {
    return _publications.where((p) => p.kind.isEmergency).toList();
  }

  List<Publication> get myPublications {
    final uid = _currentUser?.id;
    if (uid == null) return const [];
    return _publications.where((p) => p.authorId == uid).toList();
  }

  /// Reintento manual de toda la cola Outbox o de una operación específica.
  Future<OutboxSyncSummary> retryOutboxSync({String? onlyOperationId}) async {
    final user = _currentUser;
    if (user == null) {
      return const OutboxSyncSummary(
        confirmedCount: 0,
        pendingCount: 0,
        errorCount: 0,
        conflictCount: 0,
        lastMessage: 'Inicia sesión para sincronizar.',
      );
    }
    final summary = await outboxSyncService.syncPendingForUser(
      user.id,
      onlyOperationId: onlyOperationId,
    );
    _statusBannerMessage = summary.lastMessage.isNotEmpty
        ? summary.lastMessage
        : 'Reintento completado.';
    await refreshAllLocalData();
    unawaited(refreshFromServer());
    return summary;
  }

  Future<void> keepDraftAndLoadServer(String publicationId) async {
    final user = _currentUser;
    if (user == null) {
      throw StateError('Inicia sesión para revisar tus cambios.');
    }
    final remote = await remoteGateway.fetchOwnPublication(publicationId);
    if (_currentUser?.id != user.id) {
      throw StateError('La sesión cambió. Vuelve a intentarlo.');
    }
    await database.keepDraftAndAcceptRemote(remote, user.id);
    _statusBannerMessage = 'Se cargó la versión del barrio. Conservamos tu texto anterior en Borradores.';
    await refreshAllLocalData();
  }

  /// Registro de nueva cuenta vecinal y reanudación de intención pendiente.
  Future<void> registerAndSignIn({
    required String alias,
    required String email,
    required String password,
    required String neighborhood,
    required String sector,
    required double? approxLat,
    required double? approxLng,
    required bool useGpsApprox,
    String? districtUbigeo,
  }) async {
    if (districtUbigeo != null &&
        locationCatalog.district(districtUbigeo) == null) {
      throw StateError(
        'Selecciona un distrito reconocido en el catálogo INEI.',
      );
    }
    if (_currentUser == null) {
      await updateLocationPreference(
        neighborhood: neighborhood,
        sector: sector,
        districtUbigeo: districtUbigeo,
        approxLat: approxLat,
        approxLng: approxLng,
        useGpsApprox: useGpsApprox,
      );
    }
    _authActionInProgress = true;
    final authEpoch = ++_authEpoch;
    try {
      final profile = await remoteGateway.registerAccount(
        alias: alias,
        email: email,
        password: password,
        neighborhood: neighborhood,
        sector: sector,
        approxLat: approxLat,
        approxLng: approxLng,
        useGpsApprox: useGpsApprox,
        districtUbigeo: districtUbigeo,
      );
      if (_disposed || authEpoch != _authEpoch || _passwordRecoveryPending) {
        throw StateError('La sesión cambió. Vuelve a intentarlo.');
      }
      _currentUser = profile;
      await database.saveUserProfile(profile, queueSync: true);
      await outboxSyncService.syncPendingForUser(profile.id);
      await refreshAllLocalData();
      _resumePendingIntentOrGoHome();
      unawaited(refreshFromServer());
    } finally {
      _authActionInProgress = false;
    }
  }

  /// Inicio de sesión y reanudación automática de intención pendiente.
  Future<void> signIn({required String email, required String password}) async {
    _authActionInProgress = true;
    final authEpoch = ++_authEpoch;
    try {
      final remoteProfile = await remoteGateway.signInAccount(
        email: email,
        password: password,
      );
      final profile = await _preferPendingLocalProfile(remoteProfile);
      if (_disposed || authEpoch != _authEpoch || _passwordRecoveryPending) {
        throw StateError('La sesión cambió. Vuelve a intentarlo.');
      }
      _currentUser = profile;
      await database.saveUserProfile(profile, queueSync: false);
      await refreshAllLocalData();
      _resumePendingIntentOrGoHome();
      unawaited(refreshFromServer());
    } finally {
      _authActionInProgress = false;
    }
  }

  /// Cierre de sesión seguro: limpia caché privada de conversaciones/mensajes
  /// del usuario saliente y preserva sus operaciones pendientes aisladas por
  /// `owner_user_id`.
  Future<void> signOut() async {
    _authEpoch++;
    final previousId = _currentUser?.id;
    await remoteGateway.signOutAccount();
    _passwordRecoveryPending = false;
    if (previousId != null) {
      await database.clearPrivateCacheOnSignOut(previousId);
    }
    _currentUser = null;
    _selectedConversation = null;
    await refreshAllLocalData();
    goHome();
  }

  Future<void> requestPasswordReset(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw StateError('Ingresa un correo electrónico válido.');
    }
    await remoteGateway.requestPasswordReset(cleanEmail);
  }

  Future<void> completePasswordRecovery(String password) async {
    if (!_passwordRecoveryPending ||
        !remoteGateway.hasPasswordRecoverySession) {
      throw StateError(
        'Abre un enlace de recuperación válido para cambiar tu contraseña.',
      );
    }
    if (password.length < 8) {
      throw StateError('La nueva contraseña debe tener al menos 8 caracteres.');
    }
    final epoch = _authEpoch;
    await remoteGateway.updateRecoveredPassword(password);
    if (_disposed || epoch != _authEpoch) return;
    _passwordRecoveryPending = false;
    await _restoreSessionFromLink();
    if (_disposed || epoch != _authEpoch) return;
    _statusBannerMessage = 'Contraseña actualizada.';
    notifyListeners();
  }

  /// Actualiza la zona manual o preferencia de GPS aproximado sin bloquear al
  /// usuario que rechaza el permiso de ubicación.
  Future<void> updateLocationPreference({
    required String neighborhood,
    required String sector,
    required double? approxLat,
    required double? approxLng,
    required bool useGpsApprox,
    String? districtUbigeo,
  }) async {
    if (districtUbigeo != null &&
        locationCatalog.district(districtUbigeo) == null) {
      throw StateError(
        'Selecciona un distrito reconocido en el catálogo INEI.',
      );
    }
    _selectedManualUbigeo = districtUbigeo;
    _selectedManualUsesGps = useGpsApprox;
    _selectedManualNeighborhood = neighborhood;
    _selectedManualSector = sector;
    _selectedManualLat = AppConfig.roundOptionalPublicCoordinate(approxLat);
    _selectedManualLng = AppConfig.roundOptionalPublicCoordinate(approxLng);

    await database.saveManualLocation({
      'district_ubigeo': districtUbigeo,
      'neighborhood': neighborhood,
      'sector': sector,
      'approx_lat': _selectedManualLat,
      'approx_lng': _selectedManualLng,
      'use_gps_approx': useGpsApprox ? 1 : 0,
    });
    if (_currentUser != null) {
      final updated = _currentUser!.copyWith(
        neighborhood: neighborhood,
        sector: sector,
        districtUbigeo: districtUbigeo,
        clearCoordinates: approxLat == null || approxLng == null,
        approxLat: _selectedManualLat,
        approxLng: _selectedManualLng,
        useGpsApprox: useGpsApprox,
        updatedAt: DateTime.now().toUtc(),
      );
      _currentUser = updated;
      await database.saveUserProfile(updated, queueSync: true);
      await outboxSyncService.syncPendingForUser(updated.id);
    }
    await refreshAllLocalData();
  }

  void _resumePendingIntentOrGoHome() {
    final intent = _pendingAuthIntent;
    _pendingAuthIntent = null;
    if (intent == null) {
      goHome();
      return;
    }

    if (intent.targetRoute == 'publicar' && intent.presetKind != null) {
      _publishPresetKind = intent.presetKind!;
      _publishTypeLocked = intent.lockType;
      navigateTo(AppSection.publicarRapido);
      return;
    }

    if (intent.publicationId != null) {
      final match = _publications
          .where((p) => p.id == intent.publicationId)
          .toList();
      if (match.isNotEmpty) {
        _selectedPublication = match.first;
        navigateTo(
          match.first.kind.isService
              ? AppSection.detalleServicio
              : AppSection.detalleFavor,
        );
        return;
      }
    }

    goHome();
  }
}
