import 'domain_models.dart';

class EmergencyGroupMessage {
  const EmergencyGroupMessage({
    required this.id,
    required this.clientMutationId,
    required this.publicationId,
    required this.senderId,
    required this.senderAlias,
    required this.body,
    required this.createdAt,
    this.syncStatus = SyncStatus.confirmado,
    this.lastError = '',
  });
  final String id,
      clientMutationId,
      publicationId,
      senderId,
      senderAlias,
      body,
      lastError;
  final DateTime createdAt;
  final SyncStatus syncStatus;
  Map<String, Object?> toMap() => {
    'id': id,
    'client_mutation_id': clientMutationId,
    'publication_id': publicationId,
    'sender_id': senderId,
    'sender_alias': senderAlias,
    'body': body,
    'created_at': createdAt.toUtc().toIso8601String(),
    'sync_status': syncStatus.dbValue,
    'last_error': lastError,
  };
  factory EmergencyGroupMessage.fromMap(Map<String, Object?> row) =>
      EmergencyGroupMessage(
        id: row['id'] as String,
        clientMutationId: row['client_mutation_id'] as String,
        publicationId: row['publication_id'] as String,
        senderId: row['sender_id'] as String,
        senderAlias: row['sender_alias'] as String? ?? 'Vecino',
        body: row['body'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        syncStatus: SyncStatus.fromDb(
          row['sync_status'] as String? ?? 'confirmado',
        ),
        lastError: row['last_error'] as String? ?? '',
      );
}
