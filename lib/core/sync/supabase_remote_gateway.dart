import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/domain_models.dart';
import '../models/emergency_group_message.dart';

/// Resultado de sincronizar una operación de la cola Outbox hacia el backend.
class RemoteSyncResult {
  const RemoteSyncResult({
    required this.status,
    this.errorMessage = '',
    this.confirmedVersion,
  });

  final SyncStatus status;
  final String errorMessage;
  final int? confirmedVersion;
}

/// Contrato de pasarela remota para Auth, PostgREST, PostGIS RPC y Realtime.
abstract class RemoteBackendGateway {
  bool get isLiveSupabaseConnected;

  Future<UserProfile?> getCurrentSessionProfile();

  Future<UserProfile> registerAccount({
    required String email,
    required String password,
    required String alias,
    required String neighborhood,
    required String sector,
    required double? approxLat,
    required double? approxLng,
    required bool useGpsApprox,
    String? districtUbigeo,
  });

  Future<UserProfile> signInAccount({
    required String email,
    required String password,
  });

  Future<void> signOutAccount();

  Future<RemoteSyncResult> pushOutboxOperation(OutboxOperation operation);

  Future<List<Publication>> fetchPublicationsWithinRadius({
    required double? originLat,
    required double? originLng,
    required int radiusMeters,
    String? districtUbigeo,
    PublicationKind? kind,
    String? category,
    String? searchText,
    int? maxResults,
  });

  Future<ChatMessage> sendRealtimeMessage({
    required String id,
    required String clientMutationId,
    required String conversationId,
    String? recipientId,
    required String senderId,
    required String senderAlias,
    required String body,
  });

  Stream<ChatMessage> watchConversationMessages(
    String conversationId, {
    String? peerId,
  });
}

/// Implementación real conectada a Supabase (Auth, PostgREST, PostGIS RPC y Realtime)
/// con degradación segura cuando no se han inyectado `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
class SupabaseRemoteGateway implements RemoteBackendGateway {
  SupabaseRemoteGateway({this._forceSupabaseAvailable});

  final bool? _forceSupabaseAvailable;
  // Solo los tests que inyectan explícitamente false usan el doble local.
  bool get isTestDouble => _forceSupabaseAvailable == false;
  void _requireRealBackend() {
    if (!isLiveSupabaseConnected) {
      throw StateError(
        'Supabase no está configurado. No se comunicó ninguna acción.',
      );
    }
    if (simulateNetworkOffline) {
      throw StateError(
        'Sin conexión. Inicia sesión cuando recuperes internet.',
      );
    }
  }

  /// Permite simular caída o rechazo del servidor en pruebas de integración/widget
  /// y verificar la máquina de estados del Outbox (`pendiente` -> `enviando` ->
  /// `confirmado` | `error` | `conflicto`).
  bool simulateNetworkOffline = false;
  bool simulateServerError = false;
  bool simulateVersionConflict = false;

  final Map<String, UserProfile> _localRegisteredUsersByEmail = {
    'maria@pueblolibre.pe': UserProfile(
      id: 'user-vecina-maria',
      alias: 'María Castillo',
      neighborhood: 'Pueblo Libre',
      sector: 'Sector Sucre / Candamo',
      email: 'maria@pueblolibre.pe',
      bio: 'Vecina del Sector Sucre / Candamo dispuesta a apoyar en compras y costura.',
      approxLat: -12.074,
      approxLng: -77.065,
      useGpsApprox: false,
      shareResourcesConsent: false,
      updatedAt: DateTime.utc(2026, 11, 1),
    ),
    'jorge@pueblolibre.pe': UserProfile(
      id: 'user-vecino-jorge',
      alias: 'Don Jorge Alvarado',
      neighborhood: 'Pueblo Libre',
      sector: 'Sector Plaza Bolívar',
      email: 'jorge@pueblolibre.pe',
      bio:
          'Vecino jubilado en Plaza Bolívar. Préstamo de herramientas básicas.',
      approxLat: -12.077,
      approxLng: -77.063,
      useGpsApprox: false,
      shareResourcesConsent: false,
      updatedAt: DateTime.utc(2026, 11, 1),
    ),
  };

  bool lastProfileFetchWasOffline = false;
  UserProfile? _activeLocalSession;
  final Set<String> _processedIdempotencyKeys = <String>{};
  final StreamController<ChatMessage> _realtimeController =
      StreamController<ChatMessage>.broadcast();

  @override
  bool get isLiveSupabaseConnected {
    if (_forceSupabaseAvailable != null) return _forceSupabaseAvailable;
    if (!AppConfig.hasSupabaseCredentials) return false;
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  Stream<void> get signedInSessionChanges {
    if (isTestDouble || !isLiveSupabaseConnected) return const Stream.empty();
    return _client.auth.onAuthStateChange
        .where((state) => state.event == AuthChangeEvent.signedIn)
        .map((_) {});
  }

  String? _recoveryUserId;
  Stream<void> get passwordRecoveryChanges {
    if (isTestDouble || !isLiveSupabaseConnected) return const Stream.empty();
    return _client.auth.onAuthStateChange
        .where(
          (state) =>
              state.event == AuthChangeEvent.passwordRecovery &&
              state.session != null,
        )
        .map((state) {
          _recoveryUserId = state.session!.user.id;
        });
  }

  bool get hasPasswordRecoverySession =>
      isLiveSupabaseConnected &&
      _recoveryUserId != null &&
      _client.auth.currentUser?.id == _recoveryUserId &&
      _client.auth.currentSession != null;

  Future<void> requestPasswordReset(String email) async {
    _requireRealBackend();
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: AppConfig.authRedirectUrl,
    );
  }

  Future<void> updateRecoveredPassword(String password) async {
    _requireRealBackend();
    if (!hasPasswordRecoverySession) {
      throw StateError(
        'Abre un enlace de recuperación válido para cambiar tu contraseña.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));
    _recoveryUserId = null;
  }

  @override
  Future<UserProfile?> getCurrentSessionProfile() async {
    lastProfileFetchWasOffline = false;
    if (isLiveSupabaseConnected) {
      try {
        final session = _client.auth.currentSession;
        final user = _client.auth.currentUser;
        if (session == null || user == null) return null;
        final data = await _client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (data == null) {
          return UserProfile(
            id: user.id,
            alias: (user.userMetadata?['alias'] as String?) ?? 'Vecino',
            neighborhood:
                (user.userMetadata?['neighborhood'] as String?) ??
                AppConfig.defaultNeighborhood,
            sector:
                (user.userMetadata?['sector'] as String?) ??
                AppConfig.defaultSector,
            email: user.email ?? '',
            districtUbigeo: user.userMetadata?['district_ubigeo'] as String?,
            approxLat: (user.userMetadata?['approx_lat'] as num?)?.toDouble(),
            approxLng: (user.userMetadata?['approx_lng'] as num?)?.toDouble(),
            useGpsApprox: false,
            shareResourcesConsent: false,
            updatedAt: DateTime.now().toUtc(),
          );
        }
        return UserProfile(
          id: data['id'] as String,
          alias: (data['alias'] as String?) ?? 'Vecino',
          neighborhood:
              (data['neighborhood'] as String?) ??
              AppConfig.defaultNeighborhood,
          sector: (data['sector'] as String?) ?? AppConfig.defaultSector,
          email: user.email ?? '',
          bio: (data['bio'] as String?) ?? '',
          districtUbigeo: data['district_ubigeo'] as String?,
          approxLat: (data['approx_lat'] as num?)?.toDouble(),
          approxLng: (data['approx_lng'] as num?)?.toDouble(),
          useGpsApprox: (data['use_gps_approx'] as bool?) ?? false,
          shareResourcesConsent:
              (data['share_resources_consent'] as bool?) ?? false,
          updatedAt:
              DateTime.tryParse((data['updated_at'] as String?) ?? '') ??
              DateTime.now().toUtc(),
        );
      } catch (_) {
        lastProfileFetchWasOffline = true;
        final user = _client.auth.currentUser;
        if (user == null) return null;
        if (_activeLocalSession?.id == user.id) return _activeLocalSession;
        final metadata = user.userMetadata ?? {};
        return UserProfile(
          id: user.id,
          alias: metadata['alias'] as String? ?? 'Vecino',
          neighborhood:
              metadata['neighborhood'] as String? ??
              AppConfig.defaultNeighborhood,
          sector: metadata['sector'] as String? ?? AppConfig.defaultSector,
          email: user.email ?? '',
          districtUbigeo: metadata['district_ubigeo'] as String?,
          approxLat: (metadata['approx_lat'] as num?)?.toDouble(),
          approxLng: (metadata['approx_lng'] as num?)?.toDouble(),
          updatedAt: DateTime.now().toUtc(),
        );
      }
    }
    return _activeLocalSession;
  }

  @override
  Future<UserProfile> registerAccount({
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
    if (!isTestDouble && (!isLiveSupabaseConnected || simulateNetworkOffline)) {
      _requireRealBackend();
    }
    final cleanEmail = email.trim().toLowerCase();
    final cleanAlias = alias.trim();
    if (cleanAlias.length < 2) {
      throw StateError('Ingresa tu nombre o alias vecinal (mínimo 2 letras).');
    }
    if (!cleanEmail.contains('@')) {
      throw StateError('Ingresa un correo electrónico válido.');
    }
    if (password.length < 6) {
      throw StateError('La contraseña debe tener al menos 6 caracteres.');
    }

    if (isLiveSupabaseConnected && !simulateNetworkOffline) {
      final response = await _client.auth.signUp(
        email: cleanEmail,
        password: password,
        emailRedirectTo: AppConfig.authRedirectUrl,
        data: {
          'alias': cleanAlias,
          'neighborhood': neighborhood,
          'sector': sector,
          'district_ubigeo': districtUbigeo,
          'approx_lat': AppConfig.roundOptionalPublicCoordinate(approxLat),
          'approx_lng': AppConfig.roundOptionalPublicCoordinate(approxLng),
          'use_gps_approx': useGpsApprox,
        },
      );
      if (response.session == null) {
        throw StateError(
          'Cuenta creada. Confirma tu correo y luego inicia sesión.',
        );
      }
      final userId = response.user!.id;
      final roundedLat = AppConfig.roundOptionalPublicCoordinate(approxLat);
      final roundedLng = AppConfig.roundOptionalPublicCoordinate(approxLng);

      await _client.from('profiles').upsert({
        'id': userId,
        'alias': cleanAlias,
        'neighborhood': neighborhood,
        'sector': sector,
        'district_ubigeo': districtUbigeo,
        'use_gps_approx': useGpsApprox,
        'approx_lat': roundedLat,
        'approx_lng': roundedLng,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final profile = UserProfile(
        id: userId,
        alias: cleanAlias,
        neighborhood: neighborhood,
        sector: sector,
        districtUbigeo: districtUbigeo,
        email: cleanEmail,
        approxLat: roundedLat,
        approxLng: roundedLng,
        useGpsApprox: useGpsApprox,
        shareResourcesConsent: false,
        updatedAt: DateTime.now().toUtc(),
      );
      _activeLocalSession = profile;
      return profile;
    }

    if (!isTestDouble) _requireRealBackend();
    final userId = 'user-${cleanEmail.replaceAll(RegExp(r'[^a-z0-9]'), '-')}';
    final profile = UserProfile(
      id: userId,
      alias: cleanAlias,
      neighborhood: neighborhood,
      sector: sector,
      districtUbigeo: districtUbigeo,
      email: cleanEmail,
      approxLat: AppConfig.roundOptionalPublicCoordinate(approxLat),
      approxLng: AppConfig.roundOptionalPublicCoordinate(approxLng),
      useGpsApprox: useGpsApprox,
      shareResourcesConsent: false,
      updatedAt: DateTime.now().toUtc(),
    );
    _localRegisteredUsersByEmail[cleanEmail] = profile;
    _activeLocalSession = profile;
    return profile;
  }

  @override
  Future<UserProfile> signInAccount({
    required String email,
    required String password,
  }) async {
    if (!isTestDouble && (!isLiveSupabaseConnected || simulateNetworkOffline)) {
      _requireRealBackend();
    }
    final cleanEmail = email.trim().toLowerCase();
    if (!cleanEmail.contains('@')) {
      throw StateError('Ingresa un correo electrónico válido.');
    }
    if (password.isEmpty) {
      throw StateError('Ingresa tu contraseña.');
    }

    if (isLiveSupabaseConnected && !simulateNetworkOffline) {
      final response = await _client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );
      final user = response.user;
      if (user != null) {
        final profile = await getCurrentSessionProfile();
        if (profile != null) {
          _activeLocalSession = profile;
          return profile;
        }
      }
    }

    if (!isTestDouble) {
      _requireRealBackend();
      throw StateError('No se pudo recuperar la sesión autenticada.');
    }
    final existing = _localRegisteredUsersByEmail[cleanEmail];
    if (existing != null) {
      _activeLocalSession = existing;
      return existing;
    }

    final aliasFromEmail = cleanEmail.split('@').first;
    final formattedAlias = aliasFromEmail.isNotEmpty
        ? '${aliasFromEmail[0].toUpperCase()}${aliasFromEmail.substring(1)}'
        : 'Vecino';
    final created = UserProfile(
      id: 'user-${cleanEmail.replaceAll(RegExp(r'[^a-z0-9]'), '-')}',
      alias: formattedAlias,
      neighborhood: AppConfig.defaultNeighborhood,
      sector: AppConfig.defaultSector,
      email: cleanEmail,
      approxLat: AppConfig.defaultLat,
      approxLng: AppConfig.defaultLng,
      useGpsApprox: false,
      shareResourcesConsent: false,
      updatedAt: DateTime.now().toUtc(),
    );
    _localRegisteredUsersByEmail[cleanEmail] = created;
    _activeLocalSession = created;
    return created;
  }

  @override
  Future<void> signOutAccount() async {
    _activeLocalSession = null;
    _recoveryUserId = null;
    if (isLiveSupabaseConnected) {
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Future<RemoteSyncResult> pushOutboxOperation(
    OutboxOperation operation,
  ) async {
    if (simulateNetworkOffline) {
      return const RemoteSyncResult(
        status: SyncStatus.pendiente,
        errorMessage: 'Sin conexión a internet. Tu solicitud está guardada en este teléfono y aún no se ha comunicado al barrio.',
      );
    }

    if (simulateServerError) {
      return const RemoteSyncResult(
        status: SyncStatus.error,
        errorMessage: 'El servidor comunitario no respondió temporalmente. Tus datos siguen guardados en tu teléfono para reintentar.',
      );
    }

    if (simulateVersionConflict) {
      return RemoteSyncResult(
        status: SyncStatus.conflicto,
        errorMessage:
            'Conflicto de versión detectado (v${operation.expectedVersion + 1} en servidor). Revisa antes de sobrescribir.',
      );
    }

    if (!isTestDouble && !isLiveSupabaseConnected) {
      return const RemoteSyncResult(
        status: SyncStatus.pendiente,
        errorMessage: 'Supabase no configurado: guardado solo en este teléfono, NO comunicado.',
      );
    }
    if (isLiveSupabaseConnected) {
      try {
        if (operation.ownerUserId == Publication.guestOwnerId &&
            operation.entityType == 'publication') {
          final version = await _client.rpc<int>(
            'submit_guest_emergency',
            params: {'p_report': operation.decodePayload()},
          );
          return RemoteSyncResult(
            status: SyncStatus.confirmado,
            confirmedVersion: version,
          );
        }
        if (_client.auth.currentUser?.id != operation.ownerUserId) {
          throw StateError(
            'La sesión actual no pertenece al autor de esta operación.',
          );
        }
        if (!const [
          'publication',
          'publication_status',
          'publication_location',
          'emergency_group_message',
          'publication_edit',
          'publication_delete',
          'recommendation',
          'help_offer',
          'conversation',
          'profile',
        ].contains(operation.entityType)) {
          throw StateError(
            'Tipo de operación no compatible. Se conserva para revisión.',
          );
        }
        final payload = operation.decodePayload();
        switch (operation.entityType) {
          case 'publication':
            final lat = AppConfig.roundOptionalPublicCoordinate(
              (payload['approx_lat'] as num?)?.toDouble(),
            );
            final lng = AppConfig.roundOptionalPublicCoordinate(
              (payload['approx_lng'] as num?)?.toDouble(),
            );
            await _client
                .from('publications')
                .upsert(
                  {
                    'id': payload['id'],
                    'client_mutation_id': payload['client_mutation_id'],
                    'author_id': payload['author_id'],
                    'kind': payload['kind'],
                    'category': payload['category'],
                    'title': payload['title'],
                    'description': payload['description'],
                    'neighborhood': payload['neighborhood'],
                    'sector': payload['sector'],
                    if (payload.containsKey('district_ubigeo'))
                      'district_ubigeo': payload['district_ubigeo'],
                    if (payload.containsKey('share_service_location')) ...{
                      'share_service_location':
                          payload['share_service_location'] == 1 ||
                          payload['share_service_location'] == true,
                      'service_lat': payload['service_lat'],
                      'service_lng': payload['service_lng'],
                      'service_address': payload['service_address'] ?? '',
                    },
                    'availability_text': payload['availability_text'] ?? '',
                    'priority': payload['priority'],
                    'status': payload['status'],
                    'approx_lat': lat,
                    'approx_lng': lng,
                    'share_resource_consent':
                        ((payload['share_resource_consent'] as int?) ?? 0) == 1,
                    'version': payload['version'] ?? 1,
                  },
                  onConflict: 'client_mutation_id',
                  ignoreDuplicates: true,
                );
            final row = await _client
                .from('publications')
                .select('version')
                .eq('id', operation.entityId)
                .single();
            return RemoteSyncResult(
              status: SyncStatus.confirmado,
              confirmedVersion: row['version'] as int,
            );
          case 'emergency_group_message':
            await _client.rpc(
              'send_emergency_group_message',
              params: {
                'p_id': payload['id'],
                'p_mutation': payload['client_mutation_id'],
                'p_publication': payload['publication_id'],
                'p_body': payload['body'],
              },
            );
            return const RemoteSyncResult(status: SyncStatus.confirmado);
          case 'publication_edit':
          case 'publication_delete':
            final version = await _client.rpc(
              'mutate_publication',
              params: {
                'p_id': operation.entityId,
                'p_expected_version': operation.expectedVersion,
                'p_operation_id': operation.operationId,
                'p_delete': operation.entityType == 'publication_delete',
                'p_changes': payload,
              },
            );
            return RemoteSyncResult(
              status: SyncStatus.confirmado,
              confirmedVersion: version as int,
            );
          case 'publication_location':
            final version = await _client.rpc(
              'update_publication_location',
              params: {
                'p_id': operation.entityId,
                'p_expected_version': operation.expectedVersion,
                'p_operation_id': operation.operationId,
                'p_location': payload,
              },
            );
            return RemoteSyncResult(
              status: SyncStatus.confirmado,
              confirmedVersion: version as int,
            );
          case 'publication_status':
            final version = await _client.rpc(
              'transition_publication_status',
              params: {
                'p_id': operation.entityId,
                'p_status': payload['status'],
                'p_expected_version': operation.expectedVersion,
                'p_operation_id': operation.operationId,
              },
            );
            return RemoteSyncResult(
              status: SyncStatus.confirmado,
              confirmedVersion: version as int,
            );
          case 'recommendation':
            if (operation.action == 'delete') {
              await _client
                  .from('recommendations')
                  .delete()
                  .eq('id', operation.entityId);
            } else {
              await _client.from('recommendations').upsert({
                'id': payload['id'],
                'client_mutation_id': payload['client_mutation_id'],
                'publication_id': payload['publication_id'],
                'user_id': payload['user_id'],
                'comment': payload['comment'] ?? '',
              }, onConflict: 'client_mutation_id');
            }
            break;
          case 'help_offer':
            await _client.from('help_offers').upsert({
              'id': payload['id'],
              'client_mutation_id': payload['client_mutation_id'],
              'publication_id': payload['publication_id'],
              'helper_id': payload['helper_id'],
              'note': payload['note'] ?? '',
              'resource_shared': payload['resource_shared'] ?? '',
              'explicit_share_consent':
                  ((payload['explicit_share_consent'] as int?) ?? 0) == 1,
              'status': payload['status'] ?? 'enviada',
            }, onConflict: 'client_mutation_id');
            break;
          case 'conversation':
            await _client.rpc(
              'ensure_neighbor_conversation',
              params: {
                'p_id': payload['id'],
                'p_mutation': payload['client_mutation_id'],
                'p_publication': payload['publication_id'],
              },
            );
            break;
          case 'profile':
            final lat = AppConfig.roundOptionalPublicCoordinate(
              (payload['approx_lat'] as num?)?.toDouble(),
            );
            final lng = AppConfig.roundOptionalPublicCoordinate(
              (payload['approx_lng'] as num?)?.toDouble(),
            );
            await _client.from('profiles').upsert({
              'id': payload['id'],
              'alias': payload['alias'],
              'neighborhood': payload['neighborhood'],
              'sector': payload['sector'],
              if (payload.containsKey('district_ubigeo'))
                'district_ubigeo': payload['district_ubigeo'],
              'bio': payload['bio'] ?? '',
              'use_gps_approx': ((payload['use_gps_approx'] as int?) ?? 0) == 1,
              'share_resources_consent':
                  ((payload['share_resources_consent'] as int?) ?? 0) == 1,
              'approx_lat': lat,
              'approx_lng': lng,
            });
            break;
        }
      } catch (e) {
        return RemoteSyncResult(
          status: e is PostgrestException && e.code == 'PT409'
              ? SyncStatus.conflicto
              : SyncStatus.error,
          errorMessage: e is PostgrestException && e.code == 'PT409'
              ? 'La publicación cambió en otro dispositivo. Revisa antes de reemplazarla.'
              : 'No se pudo confirmar el envío. Tu contenido permanece guardado para reintentar.',
        );
      }
    }

    // Registro idempotente por operationId / client_mutation_id
    _processedIdempotencyKeys.add(operation.operationId);
    return RemoteSyncResult(
      status: SyncStatus.confirmado,
      confirmedVersion:
          operation.expectedVersion +
          (const [
                'publication_location',
                'publication_edit',
                'publication_delete',
              ].contains(operation.entityType)
              ? 1
              : 0),
    );
  }

  @override
  Future<List<Publication>> fetchPublicationsWithinRadius({
    required double? originLat,
    required double? originLng,
    required int radiusMeters,
    String? districtUbigeo,
    PublicationKind? kind,
    String? category,
    String? searchText,
    int? maxResults,
  }) async {
    if (!isLiveSupabaseConnected || simulateNetworkOffline) {
      return const [];
    }

    final rows =
        await _client
                .rpc(
                  'search_publications_by_location',
                  params: {
                    'p_lat': originLat,
                    'p_lng': originLng,
                    'p_radius_meters': radiusMeters,
                    'p_district_ubigeo': districtUbigeo,
                    'p_kind': kind?.dbValue,
                    'p_category': category,
                    'p_search': searchText,
                  },
                )
                .limit(maxResults ?? 1000)
            as List<dynamic>;
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      final map = Map<String, Object?>.from(row['publication'] as Map);
      map['owner_user_id'] = map['author_id'];
      map['author_alias'] = row['author_alias'] ?? 'Vecino';
      map['sync_status'] = 'confirmado';
      return Publication.fromSqlMap(map);
    }).toList();
  }

  @override
  Future<ChatMessage> sendRealtimeMessage({
    required String id,
    required String clientMutationId,
    required String conversationId,
    String? recipientId,
    required String senderId,
    required String senderAlias,
    required String body,
  }) async {
    if (simulateNetworkOffline) {
      throw StateError(
        'Sin conexión a internet. Los mensajes de chat requieren conexión activa; tu texto se guardó como borrador.',
      );
    }
    if (simulateServerError) {
      throw StateError(
        'El servicio de mensajería no respondió. Tu mensaje se conservó como borrador.',
      );
    }

    DateTime? createdAt;
    if (isLiveSupabaseConnected) {
      if (_client.auth.currentUser?.id != senderId) {
        throw StateError('La sesión no coincide con el remitente.');
      }
      if (recipientId != null) {
        final row = Map<String, dynamic>.from(
          await _client.rpc(
            'send_neighbor_message',
            params: {
              'p_id': id,
              'p_mutation': clientMutationId,
              'p_recipient': recipientId,
              'p_body': body.trim(),
            },
          ) as Map,
        );
        createdAt = DateTime.parse(row['created_at'] as String);
      } else {
        final row = await _client
            .from('messages')
            .upsert(
              {
                'id': id,
                'client_mutation_id': clientMutationId,
                'conversation_id': conversationId,
                'sender_id': senderId,
                'body': body.trim(),
              },
              onConflict: 'client_mutation_id',
              ignoreDuplicates: true,
            )
            .select('created_at')
            .maybeSingle();
        createdAt = DateTime.tryParse(row?['created_at'] as String? ?? '');
      }
    }

    if (!isTestDouble && !isLiveSupabaseConnected) _requireRealBackend();
    final message = ChatMessage(
      id: id,
      clientMutationId: clientMutationId,
      ownerUserId: senderId,
      conversationId: conversationId,
      senderId: senderId,
      senderAlias: senderAlias,
      body: body.trim(),
      syncStatus: SyncStatus.confirmado,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
    _realtimeController.add(message);
    return message;
  }

  Future<void> ensureNeighborConversation({
    required String id,
    required String mutationId,
    required String publicationId,
  }) async {
    if (isTestDouble) return;
    _requireRealBackend();
    await _client
        .rpc(
          'ensure_neighbor_conversation',
          params: {
            'p_id': id,
            'p_mutation': mutationId,
            'p_publication': publicationId,
          },
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<List<Map<String, Object?>>> fetchConversationList() async {
    if (isTestDouble) return const [];
    _requireRealBackend();
    final owner = _client.auth.currentUser!.id;
    final profiles = await _client.from('profiles').select('id,alias');
    final aliases = {for (final p in profiles) p['id']: p['alias']};
    final rows = await _client.from('conversations').select();
    return rows
        .map(
          (row) => <String, Object?>{
            ...row,
            'owner_user_id': owner,
            'sync_status': 'confirmado',
            'publication_author_alias':
                aliases[row['publication_author_id']] ?? 'Vecino',
            'participant_alias': aliases[row['participant_id']] ?? 'Vecino',
            'publication_title': 'Conversación vecinal',
          },
        )
        .toList();
  }

  Future<Map<String, DateTime>> fetchChatActivity(List<String> groups) async {
    if (isTestDouble) return {};
    _requireRealBackend();
    final rows = await _client.rpc(
      'get_my_chat_activity',
      params: {'p_groups': groups},
    ) as List;
    return {
      for (final row in rows)
        row['chat_key'] as String: DateTime.parse(
          row['last_message_at'] as String,
        ),
    };
  }

  Stream<void> watchChatActivity() {
    if (isTestDouble || !isLiveSupabaseConnected) return const Stream.empty();
    late StreamController<void> output;
    RealtimeChannel? channel;
    output = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('chat-list-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'conversations',
              callback: (_) {
                if (!output.isClosed) output.add(null);
              },
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'emergency_group_messages',
              callback: (_) {
                if (!output.isClosed) output.add(null);
              },
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) await _client.removeChannel(channel!);
      },
    );
    return output.stream;
  }

  Stream<ChatMessage> _watchNeighborMessages(
    String localConversationId,
    String peerId,
  ) {
    late StreamController<ChatMessage> output;
    StreamSubscription<void>? updates;
    Timer? timer;
    final owner = _client.auth.currentUser!.id;
    final seen = <String>{};
    var busy = false, cancelled = false;
    Future<void> refresh() async {
      if (cancelled ||
          busy ||
          output.isClosed ||
          simulateNetworkOffline ||
          _client.auth.currentUser?.id != owner) {
        return;
      }
      busy = true;
      try {
        DateTime? before;
        String? beforeId;
        while (!cancelled && _client.auth.currentUser?.id == owner) {
          final rows =
              await _client
                      .rpc(
                        'list_neighbor_messages_page',
                        params: {
                          'p_peer': peerId,
                          'p_before_time': before?.toUtc().toIso8601String(),
                          'p_before_id': beforeId,
                        },
                      )
                      .timeout(const Duration(seconds: 15))
                  as List;
          if (cancelled ||
              output.isClosed ||
              _client.auth.currentUser?.id != owner) {
            return;
          }
          var foundSeen = false;
          for (final row in rows) {
            if (!seen.add(row['id'] as String)) {
              foundSeen = true;
              continue;
            }
            output.add(
              ChatMessage(
                id: row['id'] as String,
                clientMutationId: row['client_mutation_id'] as String,
                ownerUserId: owner,
                conversationId: localConversationId,
                senderId: row['sender_id'] as String,
                senderAlias: row['sender_alias'] as String,
                body: row['body'] as String,
                syncStatus: SyncStatus.confirmado,
                createdAt: DateTime.parse(row['created_at'] as String),
              ),
            );
          }
          if (rows.length < 100 || foundSeen) break;
          before = DateTime.parse(rows.last['created_at'] as String);
          beforeId = rows.last['id'] as String;
        }
      } catch (error) {
        if (!cancelled && !output.isClosed) output.addError(error);
      } finally {
        busy = false;
      }
    }

    output = StreamController<ChatMessage>(
      onListen: () {
        updates = watchChatActivity().listen((_) {
          unawaited(refresh());
        });
        timer = Timer.periodic(const Duration(seconds: 10), (_) {
          unawaited(refresh());
        });
        unawaited(refresh());
      },
      onCancel: () async {
        cancelled = true;
        timer?.cancel();
        await updates?.cancel();
      },
    );
    return output.stream;
  }

  Future<List<EmergencyGroupMessage>> fetchEmergencyGroupMessages(
    String publicationId, {
    DateTime? beforeTime,
    String? beforeId,
  }) async {
    if (isTestDouble) return const [];
    _requireRealBackend();
    final rows = await _client.rpc(
      'list_emergency_group_messages',
      params: {
        'p_publication': publicationId,
        'p_before_time': beforeTime?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
      },
    ) as List<dynamic>;
    return rows
        .map(
          (row) => EmergencyGroupMessage.fromMap(
            Map<String, Object?>.from(row as Map),
          ),
        )
        .toList();
  }

  Stream<void> watchEmergencyGroup(String publicationId) {
    if (isTestDouble || !isLiveSupabaseConnected) return const Stream.empty();
    return _client
        .from('emergency_group_messages')
        .stream(primaryKey: ['id'])
        .eq('publication_id', publicationId)
        .order('created_at', ascending: false)
        .limit(100)
        .map((_) {});
  }

  Future<List<Publication>> fetchFeedPage({
    String? districtUbigeo,
    DateTime? beforeTime,
    String? beforeId,
    int limit = 30,
  }) async {
    if (isTestDouble) return const [];
    _requireRealBackend();
    final rows = await _client.rpc(
      'neighborhood_feed',
      params: {
        'p_district': districtUbigeo ?? '',
        'p_before_time': beforeTime?.toUtc().toIso8601String(),
        'p_before_id': beforeId,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      return Publication.fromSqlMap({
        ...Map<String, Object?>.from(row['publication'] as Map),
        'author_alias': row['author_alias'],
        'owner_user_id': row['publication']['author_id'],
        'sync_status': 'confirmado',
      });
    }).toList();
  }

  Future<List<Publication>> fetchCachedPublicationUpdates(
    List<Publication> cached,
  ) async {
    if (isTestDouble || cached.isEmpty) return const [];
    _requireRealBackend();
    final byId = {for (final p in cached) p.id: p};
    final result = <Publication>[];
    for (var i = 0; i < cached.length; i += 100) {
      final ids = cached.skip(i).take(100).map((p) => p.id).toList();
      final versions = await _client
          .from('publications')
          .select('id,version')
          .inFilter('id', ids)
          .isFilter('deleted_at', null);
      final changed = versions
          .where((r) => (r['version'] as int) > byId[r['id']]!.version)
          .map((r) => r['id'] as String)
          .toList();
      if (changed.isEmpty) continue;
      final rows = await _client
          .from('publications')
          .select()
          .inFilter('id', changed)
          .isFilter('deleted_at', null);
      result.addAll(
        rows.map(
          (row) => Publication.fromSqlMap({
            ...Map<String, Object?>.from(row),
            'author_alias': byId[row['id']]!.authorAlias,
            'owner_user_id': row['author_id'],
            'sync_status': 'confirmado',
          }),
        ),
      );
    }
    return result;
  }

  Future<List<Map<String, Object?>>> fetchPublicationTombstones(
    List<String> ids,
  ) async {
    if (isTestDouble || ids.isEmpty) return const [];
    _requireRealBackend();
    final result = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += 100) {
      final part = ids.skip(i).take(100).toList();
      final rows = await _client
          .from('publication_tombstones')
          .select('publication_id,deleted_at')
          .inFilter('publication_id', part);
      result.addAll(rows.map((row) => Map<String, Object?>.from(row)));
    }
    return result;
  }

  Future<Map<String, dynamic>> fetchCommunityIntelligence({
    required String district,
    required double radius,
    required int windowMinutes,
    required int minimumNeighbors,
    String? requestId,
    String? afterId,
  }) async {
    _requireRealBackend();
    final result = await _client.rpc(
      requestId == null
          ? 'community_risk_snapshot'
          : 'community_help_candidates',
      params: requestId == null
          ? {
              'p_district': district,
              'p_radius': radius,
              'p_minutes': windowMinutes,
              'p_minimum': minimumNeighbors,
            }
          : {'p_request': requestId, 'p_after': afterId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Publication?> fetchIntelligencePublication(String id) async {
    _requireRealBackend();
    final row = await _client
        .from('publications')
        .select('*,profiles!publications_author_id_fkey(alias)')
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(const Duration(seconds: 12));
    if (row == null) return null;
    return Publication.fromSqlMap({
      ...row,
      'owner_user_id': row['author_id'],
      'author_alias': (row['profiles'] as Map?)?['alias'] ?? 'Vecino',
      'sync_status': 'confirmado',
    });
  }

  Future<List<Publication>> fetchOwnMapPublications() async {
    _requireRealBackend();
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('publications')
        .select()
        .eq('author_id', user.id)
        .order('created_at', ascending: false)
        .limit(200);
    return rows
        .map(
          (row) => Publication.fromSqlMap({
            ...Map<String, Object?>.from(row),
            'owner_user_id': user.id,
            'author_alias': _activeLocalSession?.alias ?? 'Vecino',
            'sync_status': 'confirmado',
          }),
        )
        .toList();
  }

  Future<Publication> fetchOwnPublication(String id) async {
    _requireRealBackend();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Inicia sesión para revisar el cambio.');
    final row = await _client
        .from('publications')
        .select()
        .eq('id', id)
        .eq('author_id', user.id)
        .single();
    final map = Map<String, Object?>.from(row);
    map['owner_user_id'] = user.id;
    map['author_alias'] = _activeLocalSession?.alias ?? 'Vecino';
    map['sync_status'] = 'confirmado';
    return Publication.fromSqlMap(map);
  }

  Future<List<CommunityResource>> fetchMapResources({
    required double originLat,
    required double originLng,
    int radiusMeters = 20000,
    int maxResults = 201,
  }) async {
    _requireRealBackend();
    if (_client.auth.currentUser == null) return const [];
    final rows =
        await _client
                .rpc(
                  'search_resources_within_radius',
                  params: {
                    'p_lat': originLat,
                    'p_lng': originLng,
                    'p_radius_meters': radiusMeters,
                  },
                )
                .limit(maxResults)
            as List<dynamic>;
    return rows
        .where((row) => row['public_lat'] is num && row['public_lng'] is num)
        .map(
          (row) => CommunityResource.fromSqlMap({
            ...Map<String, Object?>.from(row as Map),
            'approx_lat': row['public_lat'],
            'approx_lng': row['public_lng'],
          }),
        )
        .toList();
  }

  /// Descarga datos mediante la sesión del usuario; RLS filtra los privados.
  Future<Map<String, List<Map<String, Object?>>>>
  fetchCommunitySnapshot() async {
    if (!isLiveSupabaseConnected || simulateNetworkOffline) return {};
    final user = _client.auth.currentUser;
    if (user == null) return {};
    final profiles = await _client.from('profiles').select('id,alias');
    final aliases = {for (final p in profiles) p['id']: p['alias']};
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'recommendations',
      'help_offers',
      'conversations',
      'community_resources',
      'support_groups',
    ]) {
      final rows = await _client.from(table).select();
      result[table] = rows.map((row) {
        final map = Map<String, Object?>.from(row);
        map['owner_user_id'] = user.id;
        map['sync_status'] = 'confirmado';
        if (table == 'recommendations') {
          map['user_alias'] = aliases[row['user_id']] ?? 'Vecino';
        }
        if (table == 'help_offers') {
          map['helper_alias'] = aliases[row['helper_id']] ?? 'Vecino';
        }
        if (table == 'conversations') {
          map['publication_author_alias'] =
              aliases[row['publication_author_id']] ?? 'Vecino';
          map['participant_alias'] = aliases[row['participant_id']] ?? 'Vecino';
          map['publication_title'] = 'Conversación del barrio';
        }
        return map;
      }).toList();
    }
    return result;
  }

  Future<bool> privateMessagePushEnabled() async {
    if (!isLiveSupabaseConnected || _client.auth.currentUser == null) {
      return false;
    }
    return _client.rpc<bool>('private_message_push_enabled');
  }

  Future<void> setPrivateMessagePush(
    String userId,
    String? installationId,
  ) async {
    if (!isLiveSupabaseConnected || _client.auth.currentUser?.id != userId) {
      throw StateError('La sesión cambió.');
    }
    await _client.rpc<void>(
      'set_private_message_push',
      params: {'p_user_id': userId, 'p_installation_id': installationId},
    );
  }

  Future<ConversationThread?> fetchPrivateConversation(
    String conversationId,
  ) async {
    if (!isLiveSupabaseConnected || simulateNetworkOffline) return null;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('conversations')
        .select(
          '*, author:profiles!conversations_publication_author_id_fkey(alias), '
          'participant:profiles!conversations_participant_id_fkey(alias), '
          'publications(title)',
        )
        .eq('id', conversationId)
        .maybeSingle();
    if (row == null || _client.auth.currentUser?.id != userId) return null;
    final thread = ConversationThread.fromSqlMap({
      ...row,
      'owner_user_id': userId,
      'publication_author_alias': (row['author'] as Map?)?['alias'],
      'participant_alias': (row['participant'] as Map?)?['alias'],
      'publication_title': (row['publications'] as Map?)?['title'],
    });
    return thread.involvesUser(userId) ? thread : null;
  }

  @override
  Stream<ChatMessage> watchConversationMessages(
    String conversationId, {
    String? peerId,
  }) {
    if (isLiveSupabaseConnected && peerId != null) {
      return _watchNeighborMessages(conversationId, peerId);
    }
    if (isLiveSupabaseConnected) {
      return _client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at')
          .expand(
            (rows) => rows.map(
              (row) => ChatMessage(
                id: row['id'] as String,
                clientMutationId: row['client_mutation_id'] as String,
                ownerUserId: _client.auth.currentUser!.id,
                conversationId: row['conversation_id'] as String,
                senderId: row['sender_id'] as String,
                senderAlias: row['sender_id'] == _client.auth.currentUser?.id
                    ? 'Tú'
                    : 'Vecino',
                body: row['body'] as String,
                syncStatus: SyncStatus.confirmado,
                createdAt: DateTime.parse(row['created_at'] as String),
              ),
            ),
          );
    }
    return _realtimeController.stream.where(
      (msg) => msg.conversationId == conversationId,
    );
  }
}
