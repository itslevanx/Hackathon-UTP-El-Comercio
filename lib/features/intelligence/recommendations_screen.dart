import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/intelligence/community_intelligence.dart';
import '../../core/intelligence/intelligence_controller.dart';
import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    required this.app,
    required this.requestId,
  });
  final AppController app;
  final String requestId;
  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  late final IntelligenceController _data;
  String? _category;
  bool _distanceSort = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _data = IntelligenceController(widget.app, requestId: widget.requestId);
    unawaited(_data.refresh());
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _open(HelpRecommendation match) async {
    if (_data.stale) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(match.offer['title'] as String),
          scrollable: true,
          content: Text(
            '${match.offer['description']}\n\nCopia guardada; disponibilidad sin verificar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      final pub = await widget.app.remoteGateway.fetchIntelligencePublication(
        match.id,
      );
      if (!mounted) return;
      if (pub == null || pub.status != PublicationStatus.abierta) {
        setState(() => _error = 'Esta publicación ya no está disponible.');
        await _data.refresh();
        return;
      }
      Navigator.pop(context);
      if (pub.kind.isService) {
        widget.app.openServiceDetail(pub);
      } else {
        widget.app.openFavorDetail(pub);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo comprobar la publicación. Reintenta con conexión.',
        );
      }
    }
  }

  Future<void> _contact(HelpRecommendation match) async {
    final owner = widget.app.currentUser?.id;
    final text = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mensaje para el vecino'),
        content: TextField(
          controller: text,
          maxLength: 1000,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Escribe tu consulta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('Enviar mensaje'),
          ),
        ],
      ),
    );
    // Dispose after the dialog route has finished its exit transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (!mounted ||
        message == null ||
        message.isEmpty ||
        _data.stale ||
        owner != widget.app.currentUser?.id) {
      return;
    }
    try {
      final pub = await widget.app.remoteGateway.fetchIntelligencePublication(
        match.id,
      );
      if (pub == null || pub.status != PublicationStatus.abierta) {
        await _data.refresh();
        return;
      }
      if (!mounted || _data.stale || owner != widget.app.currentUser?.id) {
        return;
      }
      await widget.app.requestContactWithProvider(
        publication: pub,
        initialMessage: message,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo abrir el chat. Reintenta con conexión.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ayudas recomendadas')),
    body: ListenableBuilder(
      listenable: _data,
      builder: (context, _) {
        final matches = _data.matches
            .where((m) => _category == null || m.offer['category'] == _category)
            .toList();
        if (_distanceSort) {
          matches.sort((a, b) {
            final d = (a.distanceMeters ?? 1 << 30).compareTo(
              b.distanceMeters ?? 1 << 30,
            );
            return d != 0 ? d : a.id.compareTo(b.id);
          });
        }
        final categories =
            _data.matches
                .map((m) => m.offer['category'] as String)
                .toSet()
                .toList()
              ..sort();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Puntaje orientativo según categoría, cercanía, oferta abierta y prioridad. No es una probabilidad de éxito.',
            ),
            if (_data.fetchedAt != null)
              Text(
                '${_data.stale ? "Datos guardados" : "Consulta actualizada"}: ${_data.fetchedAt!.toLocal()}',
              ),
            if (_data.notice != null) Text(_data.notice!),
            if (_error != null) Text(_error!),
            if (_data.loading) const LinearProgressIndicator(),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _data.loading ? null : _data.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                ),
                FilterChip(
                  label: const Text('Ordenar por distancia'),
                  selected: _distanceSort,
                  onSelected: (v) => setState(() => _distanceSort = v),
                ),
              ],
            ),
            if (categories.length > 1)
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todas'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(CommunityCategories.label(c)),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
            if (_data.snapshot?['next_cursor'] != null)
              OutlinedButton(
                onPressed: _data.loading || _data.stale
                    ? null
                    : () => _data.refresh(more: true),
                child: const Text('Cargar más ofertas'),
              ),
            if (matches.isEmpty && !_data.loading)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_data.emptyMatchesMessage),
              ),
            for (final m in matches)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: Icon(Icons.handshake_outlined),
                          label: Text('Match'),
                        ),
                      ),
                      Text(
                        'SOLICITA · ${(_data.snapshot?['request'] as Map?)?['author_alias'] ?? widget.app.currentUser?.alias ?? 'Vecino'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        (_data.snapshot?['request'] as Map?)?['title']
                                as String? ??
                            'Solicitud de ayuda',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Icon(Icons.swap_vert),
                      ),
                      const Text(
                        'OFRECE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        m.offer['title'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('Vecino: ${m.offer['author_alias'] ?? "Vecino"}'),
                      Text(
                        'Puntaje: ${m.score.round()}/100 · ${CommunityCategories.label(m.offer['category'] as String)}',
                      ),
                      for (final reason in m.explanations) Text(reason),
                      if (_data.stale)
                        const Text(
                          'Datos guardados; la oferta puede haber cambiado.',
                        ),
                      OutlinedButton(
                        onPressed: () => _open(m),
                        child: const Text('Ver detalle'),
                      ),
                      FilledButton.icon(
                        onPressed: _data.stale ? null : () => _contact(m),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Contactar'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
