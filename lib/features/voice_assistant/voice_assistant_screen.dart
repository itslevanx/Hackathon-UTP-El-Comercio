import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models/domain_models.dart';
import '../../core/geography/peru_location_catalog.dart';
import '../../core/state/app_controller.dart';
import '../shared/peru_location_selector.dart';
import 'voice_analysis.dart';
import 'voice_controller.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key, required this.app, this.voice});
  final AppController app;
  final VoiceController? voice;
  static const labels = {
    'general': 'Sin clasificar',
    'sismo': 'Sismo',
    'incendio': 'Incendio',
    'inundacion': 'Inundación',
    'derrumbe': 'Derrumbe',
    'corte_servicios': 'Corte de servicios',
    'accidente': 'Accidente',
    'agua': 'Agua',
    'alimentos': 'Alimentos',
    'medicamentos': 'Medicamentos',
    'herramientas': 'Herramientas',
    'transporte': 'Transporte',
    'refugio': 'Refugio temporal',
    'asistencia': 'Asistencia',
  };
  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen>
    with WidgetsBindingObserver {
  late final VoiceController voice;
  late final VoiceAnalyzer analyzer;
  final _text = TextEditingController();
  VoiceAnalysis? analysis;
  PeruLocationSelection zone = const PeruLocationSelection.empty();
  String category = 'general';
  VoiceAttention attention = VoiceAttention.baja;
  String? _error;
  bool _continuing = false;
  String _transcript = '';
  bool _manualZone = false;
  bool _manualCategory = false, _manualAttention = false;

  @override
  void initState() {
    super.initState();
    voice = widget.voice ?? VoiceController();
    analyzer = VoiceAnalyzer(widget.app.locationCatalog);
    WidgetsBinding.instance.addObserver(this);
    voice.addListener(_voiceChanged);
    unawaited(voice.checkModel());
  }

  void _voiceChanged() {
    if (!mounted) return;
    if (voice.text.isNotEmpty && voice.text != _transcript) {
      _transcript = voice.text;
      _text.text = voice.text;
      _analyze();
    }
    setState(() {});
  }

  void _analyze() {
    final result = analyzer.analyze(_text.text);
    setState(() {
      analysis = result;
      if (!_manualCategory) category = result.category;
      if (!_manualAttention) attention = result.attention;
      if (!_manualZone && result.districts.length == 1) {
        final d = result.districts.single;
        zone = PeruLocationSelection(
          departmentCode: d.departmentCode,
          provinceCode: d.provinceCode,
          districtCode: d.code,
        );
      } else if (!_manualZone) {
        zone = const PeruLocationSelection.empty();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && voice.busy) {
      unawaited(voice.cancel());
    }
  }

  Future<void> _download() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Preparar voz sin internet'),
        content: const Text(
          'Descargar modelo de español y otros idiomas (60 MB) desde Hugging Face. Puede usar datos móviles. Después podrás transcribir sin internet. Tu audio nunca se envía.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (allowed == true && mounted) await voice.download();
  }

  Future<void> _continue() async {
    if (_continuing || voice.busy) return;
    if (_text.text.trim().isEmpty ||
        _text.text.length > 1000 ||
        zone.districtCode == null) {
      setState(
        () => _error = 'Escribe o dicta la descripción (hasta 1.000 caracteres) y confirma el distrito.',
      );
      return;
    }
    final owner = widget.app.currentUser?.id;
    if (owner == null) {
      setState(() => _error = 'Inicia sesión para preparar tu publicación.');
      return;
    }
    setState(() => _continuing = true);
    final kind =
        [
              'sismo',
              'incendio',
              'inundacion',
              'derrumbe',
              'accidente',
            ].contains(category) ||
            attention == VoiceAttention.inmediata
        ? PublicationKind.emergenciaSolicitud
        : PublicationKind.favorSolicitud;
    try {
      final previous = await widget.app.database.getDraft(
        ownerUserId: owner,
        draftKey: 'publish_${kind.dbValue}',
      );
      if (previous != null &&
          (previous.title.isNotEmpty || previous.description.isNotEmpty)) {
        if (!mounted) return;
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Ya tienes un borrador'),
            content: const Text(
              'Se conservará una copia del borrador anterior y el dictado se abrirá en el formulario.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Usar dictado'),
              ),
            ],
          ),
        );
        if (replace != true) return;
        await widget.app.database.saveDraft(
          FormDraft.fromSqlMap({
            ...previous.toSqlMap(),
            'draft_key':
                'voice_backup_${DateTime.now().microsecondsSinceEpoch}',
          }),
        );
      }
      await widget.app.database.saveDraft(
        FormDraft(
          draftKey: 'publish_${kind.dbValue}',
          ownerUserId: owner,
          kind: kind,
          title: _text.text.trim().substring(
            0,
            _text.text.trim().length.clamp(0, 100),
          ),
          description: _text.text.trim(),
          category: category,
          availabilityText: '',
          priority: attention.publicationPriority,
          locationJson: jsonEncode({
            'voice_prefill': {
              'district_ubigeo': zone.districtCode,
              'priority': attention.publicationPriority.dbValue,
            },
          }),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted || owner != widget.app.currentUser?.id) return;
      Navigator.pop(context);
      widget.app.openQuickPublish(
        presetKind: kind,
        lockTypeForTwoClickFlow: true,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo guardar el borrador. Tu texto sigue aquí.',
        );
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    voice.removeListener(_voiceChanged);
    voice.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cuéntanos qué necesitas')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text(
            'Si hay peligro inmediato, contacta a los servicios oficiales. Conecta2 no sustituye su atención.',
          ),
          const SizedBox(height: 16),
          if (voice.modelPath == null && voice.stage != VoiceStage.downloading)
            OutlinedButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download),
              label: const Text('Preparar voz offline · 60 MB'),
            ),
          if (voice.stage == VoiceStage.downloading) ...[
            LinearProgressIndicator(
              value: voice.progress,
              semanticsLabel: 'Descargando modelo de voz',
            ),
            Text('${(voice.progress * 100).round()} %'),
          ],
          if (voice.stage == VoiceStage.recording)
            Semantics(
              liveRegion: true,
              child: Text('Grabando · máximo 30 segundos'),
            ),
          if (voice.stage == VoiceStage.processing)
            Semantics(
              liveRegion: true,
              child: Text('Transcribiendo en este teléfono…'),
            ),
          if (voice.stage == VoiceStage.preparing)
            const Text('Preparando micrófono…'),
          if (voice.stage == VoiceStage.cancelling)
            const Text('Cancelando y liberando el audio…'),
          if (voice.stage == VoiceStage.processing ||
              voice.stage == VoiceStage.cancelling)
            const LinearProgressIndicator(),
          if (voice.error.isNotEmpty)
            Semantics(liveRegion: true, child: Text(voice.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('voice_record'),
            onPressed: voice.stage == VoiceStage.recording
                ? voice.stop
                : (voice.busy || voice.modelPath == null ? null : voice.start),
            icon: Icon(
              voice.stage == VoiceStage.recording ? Icons.stop : Icons.mic,
            ),
            label: Text(
              voice.stage == VoiceStage.recording
                  ? 'Terminar grabación'
                  : 'Hablar',
            ),
          ),
          if (voice.busy)
            OutlinedButton(
              onPressed: voice.stage == VoiceStage.cancelling
                  ? null
                  : voice.cancel,
              child: const Text('Cancelar grabación'),
            ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('voice_transcript'),
            controller: _text,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            enabled: !voice.busy,
            decoration: const InputDecoration(
              labelText: 'Tu descripción',
              hintText: 'También puedes escribir aquí.',
            ),
            onChanged: (_) => _analyze(),
          ),
          if (analysis != null) ...[
            Text('Sugerencia orientativa: ${analysis!.attention.label}'),
            if (analysis!.uncertain)
              const Text(
                'La descripción expresa incertidumbre. Confirma lo que observaste.',
              ),
            for (final reason in analysis!.reasons) Text(reason),
            if (analysis!.resources.isNotEmpty)
              Text(
                'Recursos mencionados: ${analysis!.resources.map((r) => VoiceAssistantScreen.labels[r] ?? r).join(', ')}',
              ),
            if (analysis!.quantities.isNotEmpty)
              Text('Cantidades: ${analysis!.quantities.join(', ')}'),
            if (analysis!.districts.length > 1)
              const Text(
                'Hay varios distritos con ese nombre. Confirma departamento, provincia y distrito.',
              ),
            if (analysis!.missing.isNotEmpty)
              Text('Por revisar: ${analysis!.missing.join(', ')}'),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey('voice_category_$category'),
            initialValue: category,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Tipo de situación'),
            items: VoiceAssistantScreen.labels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: voice.busy
                ? null
                : (v) {
                    if (v != null) {
                      setState(() {
                        category = v;
                        _manualCategory = true;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<VoiceAttention>(
            key: ValueKey('voice_priority_${attention.name}'),
            initialValue: attention,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Prioridad orientativa',
            ),
            items: VoiceAttention.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: voice.busy
                ? null
                : (v) {
                    if (v != null) {
                      setState(() {
                        attention = v;
                        _manualAttention = true;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),
          PeruLocationSelector(
            catalog: widget.app.locationCatalog,
            value: zone,
            isRequired: true,
            enabled: !voice.busy,
            onChanged: (v) => setState(() {
              zone = v;
              _manualZone = true;
            }),
          ),
          const Text(
            'La ubicación mencionada no es tu GPS. No se publica una dirección exacta.',
          ),
          if (_error != null) Text(_error!),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('voice_continue'),
            onPressed: voice.busy || _continuing ? null : _continue,
            child: const Text('Revisar formulario'),
          ),
          const Text(
            'Todavía no se publica nada. Podrás corregir el formulario y confirmar el envío.',
          ),
        ],
      ),
    ),
  );
}
