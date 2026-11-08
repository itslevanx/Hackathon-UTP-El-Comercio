import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Burbuja compartida por las conversaciones privadas y los grupos.
class ConversationMessageBubble extends StatelessWidget {
  const ConversationMessageBubble({
    super.key,
    required this.isMine,
    required this.senderAlias,
    required this.body,
    required this.createdAt,
    this.status,
  });
  final bool isMine;
  final String senderAlias, body;
  final DateTime createdAt;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final date = createdAt.toLocal();
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * .8),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFFBCEAD0) : const Color(0xFFE9EDF2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMine ? 'Tú' : senderAlias,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 17,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}/${date.month} · $time',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              ?status,
            ],
          ),
        ),
      ),
    );
  }
}
