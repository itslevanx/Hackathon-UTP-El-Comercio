final class PrivateMessageNotice {
  const PrivateMessageNotice._(
    this.conversationId,
    this.recipientId,
    this.messageId,
  );

  final String conversationId;
  final String recipientId;
  final String messageId;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static PrivateMessageNotice? fromData(Map<String, dynamic> data) {
    if (data['type'] != 'private_message') return null;
    final conversation = data['conversation_id'];
    final recipient = data['recipient_id'];
    final message = data['message_id'];
    if (conversation is! String ||
        recipient is! String ||
        message is! String ||
        !_uuid.hasMatch(conversation) ||
        !_uuid.hasMatch(recipient) ||
        !_uuid.hasMatch(message)) {
      return null;
    }
    return PrivateMessageNotice._(
      conversation.toLowerCase(),
      recipient.toLowerCase(),
      message.toLowerCase(),
    );
  }
}
