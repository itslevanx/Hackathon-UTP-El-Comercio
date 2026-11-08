import '../../core/intelligence/community_intelligence.dart';

import 'package:flutter/material.dart';

import '../../core/accessibility/text_input_support.dart';
import '../../core/models/domain_models.dart';
import '../../core/state/app_controller.dart';

class PublicationOwnerActions extends StatelessWidget {
  const PublicationOwnerActions({
    super.key,
    required this.controller,
    required this.publication,
  });
  final AppController controller;
  final Publication publication;
  @override
  Widget build(BuildContext context) {
    if (controller.currentUser?.id != publication.authorId ||
        publication.isDeleted) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          key: ValueKey('edit_publication_${publication.id}'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditPublicationScreen(
                controller: controller,
                publication: publication,
              ),
            ),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar'),
        ),
        if ([
              PublicationKind.favorOferta,
              PublicationKind.emergenciaOferta,
              PublicationKind.donacion,
              PublicationKind.prestamo,
            ].contains(publication.kind) &&
            publication.status == PublicationStatus.abierta)
          TextButton.icon(
            onPressed: () async {
              try {
                await controller.updatePublicationStatus(
                  publicationId: publication.id,
                  newStatus: PublicationStatus.resuelta,
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo actualizar la disponibilidad.'),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Marcar recurso agotado'),
          ),
        TextButton.icon(
          key: ValueKey('delete_publication_${publication.id}'),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                scrollable: true,
                title: const Text('¿Eliminar publicación?'),
                content: const Text(
                  'Se quitará de los avisos y del mapa. Tus conversaciones se conservan. Sin internet, la eliminación llegará al barrio cuando se sincronice.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Conservar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            try {
              await controller.deletePublication(publication);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Publicación eliminada de este teléfono. Los cambios pendientes se enviarán al recuperar conexión.',
                    ),
                  ),
                );
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No se pudo eliminar. Tu publicación se conserva.',
                    ),
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar'),
        ),
      ],
    );
  }
}

class EditPublicationScreen extends StatefulWidget {
  const EditPublicationScreen({
    super.key,
    required this.controller,
    required this.publication,
  });
  final AppController controller;
  final Publication publication;
  @override
  State<EditPublicationScreen> createState() => _EditPublicationScreenState();
}

class _EditPublicationScreenState extends State<EditPublicationScreen> {
  final _form = GlobalKey<FormState>();
  late String _category = widget.publication.category;
  late final _title = TextEditingController(text: widget.publication.title);
  late final _description = TextEditingController(
    text: widget.publication.description,
  );
  late final _availability = TextEditingController(
    text: widget.publication.availabilityText,
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _availability.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editar publicación')),
    body: SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.publication.kind.label),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Categoría del recurso o incidente',
                ),
                items:
                    {
                          _category: CommunityCategories.label(_category),
                          ...CommunityCategories.labels,
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _category = v);
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('edit_publication_title'),
                controller: _title,
                maxLength: 120,
                contextMenuBuilder: buildTextSelectionToolbar,
                onTapOutside: dismissTextInput,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (s) => (s?.trim().length ?? 0) < 3
                    ? 'Escribe al menos 3 caracteres.'
                    : null,
              ),
              TextFormField(
                key: const Key('edit_publication_description'),
                controller: _description,
                maxLength: 1000,
                minLines: 3,
                maxLines: 8,
                contextMenuBuilder: buildTextSelectionToolbar,
                onTapOutside: dismissTextInput,
                decoration: const InputDecoration(labelText: 'Descripción'),
                validator: (s) =>
                    (s?.trim().isEmpty ?? true) ? 'Describe tu aviso.' : null,
              ),
              if (widget.publication.kind.isService)
                TextFormField(
                  controller: _availability,
                  maxLength: 200,
                  contextMenuBuilder: buildTextSelectionToolbar,
                  onTapOutside: dismissTextInput,
                  decoration: const InputDecoration(
                    labelText: 'Disponibilidad',
                  ),
                ),
              const Text(
                'Puedes cambiar el punto desde Explorar mapa. Sin conexión, los cambios se guardan en este teléfono y quedan pendientes de envío.',
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('save_publication_edit'),
                onPressed: _saving
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() {
                          _saving = true;
                          _error = null;
                        });
                        try {
                          await widget.controller.editPublication(
                            widget.publication,
                            title: _title.text,
                            description: _description.text,
                            category: _category,
                            availabilityText: _availability.text,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => _error = 'No se pudo guardar. El texto sigue en el formulario.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
