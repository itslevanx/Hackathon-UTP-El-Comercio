import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:conecta2_voice/conecta2_voice.dart';

import 'voice_audio.dart';
import 'voice_model_store.dart';

abstract interface class VoiceTranscriber {
  Future<String> transcribe(String model, String audio);
  Future<void> cancel();
}

class DeviceVoiceTranscriber implements VoiceTranscriber {
  final _engine = LocalWhisper();
  @override
  Future<String> transcribe(String model, String audio) =>
      _engine.transcribe(model, audio);
  @override
  Future<void> cancel() => _engine.cancel();
}

enum VoiceStage {
  idle,
  downloading,
  preparing,
  recording,
  processing,
  cancelling,
  review,
  error,
}

class VoiceController extends ChangeNotifier {
  VoiceController({
    VoiceAudio Function()? audioFactory,
    VoiceTranscriber? transcriber,
    VoiceModelStore? models,
  }) : audioFactory = audioFactory ?? DeviceVoiceAudio.new,
       transcriber = transcriber ?? DeviceVoiceTranscriber(),
       models = models ?? VoiceModelStore();
  final VoiceAudio Function() audioFactory;
  final VoiceTranscriber transcriber;
  final VoiceModelStore models;
  VoiceAudio? _audio;
  Timer? _limit;
  bool _disposed = false;
  int _epoch = 0;
  VoiceStage stage = VoiceStage.idle;
  String text = '', error = '';
  String? modelPath;
  double progress = 0;
  bool get busy => [
    VoiceStage.downloading,
    VoiceStage.preparing,
    VoiceStage.recording,
    VoiceStage.processing,
    VoiceStage.cancelling,
  ].contains(stage);
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> checkModel() async {
    try {
      modelPath = await models.readyPath();
    } catch (_) {
      modelPath = null;
      error = 'No se pudo revisar el modelo local.';
    }
    _emit();
  }

  Future<void> download() async {
    if (busy) return;
    stage = VoiceStage.downloading;
    error = '';
    _emit();
    final epoch = ++_epoch;
    try {
      final path = await models.download((value) {
        if (!_disposed && epoch == _epoch) {
          progress = value;
          _emit();
        }
      });
      if (!_disposed && epoch == _epoch) {
        modelPath = path;
        stage = VoiceStage.idle;
      }
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        error = 'No se descargó el modelo. Revisa la conexión y vuelve a intentarlo.';
        stage = VoiceStage.error;
      }
    }
    _emit();
  }

  Future<void> start() async {
    if (busy || modelPath == null || _disposed) return;
    final epoch = ++_epoch;
    stage = VoiceStage.preparing;
    error = '';
    _emit();
    final audio = audioFactory();
    _audio = audio;
    try {
      await audio.start();
      if (epoch != _epoch || _disposed) {
        await _release(audio);
        return;
      }
      stage = VoiceStage.recording;
      _emit();
      _limit = Timer(const Duration(seconds: 30), () {
        unawaited(stop());
      });
    } catch (_) {
      await _release(audio);
      _audio = null;
      if (epoch == _epoch && !_disposed) {
        stage = VoiceStage.error;
        error = 'No se pudo usar el micrófono. Revisa el permiso o escribe tu aviso.';
        _emit();
      }
    }
  }

  Future<void> stop() async {
    if (stage != VoiceStage.recording || _disposed) return;
    _limit?.cancel();
    stage = VoiceStage.processing;
    _emit();
    final epoch = _epoch;
    final audio = _audio;
    try {
      final path = await audio?.stop();
      if (epoch != _epoch || _disposed) return;
      if (path == null) throw StateError('Audio no disponible');
      final transcript = await transcriber.transcribe(modelPath!, path);
      if (epoch == _epoch && !_disposed) {
        text = transcript;
        stage = transcript.isEmpty ? VoiceStage.error : VoiceStage.review;
        error = transcript.isEmpty
            ? 'No se reconoció voz. Puedes repetir o escribir.'
            : '';
      }
    } catch (_) {
      if (epoch == _epoch && !_disposed) {
        stage = VoiceStage.error;
        error = 'No se pudo transcribir. Puedes repetir o escribir el aviso.';
      }
    } finally {
      await _release(audio);
      if (identical(_audio, audio)) _audio = null;
      _emit();
    }
  }

  Future<void> cancel() async {
    if (stage == VoiceStage.cancelling) return;
    ++_epoch;
    _limit?.cancel();
    stage = VoiceStage.cancelling;
    _emit();
    models.cancelDownload();
    final audio = _audio;
    _audio = null;
    try {
      await transcriber.cancel();
    } catch (_) {
      /* Release capture even if the engine failed. */
    }
    await _release(audio);
    if (!_disposed) {
      stage = VoiceStage.idle;
      _emit();
    }
  }

  Future<void> _release(VoiceAudio? audio) async {
    try {
      await audio?.dispose();
    } catch (_) {
      if (!_disposed) {
        stage = VoiceStage.error;
        error = 'No se pudo liberar el audio temporal. Vuelve a intentarlo.';
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
