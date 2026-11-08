import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

abstract interface class VoiceAudio {
  Future<void> start();
  Future<String?> stop();
  Future<void> dispose();
}

class DeviceVoiceAudio implements VoiceAudio {
  static DeviceVoiceAudio? _owner;
  static Future<void> clearStaleAudio() async {
    if (_owner != null) return;
    final temp = await getTemporaryDirectory();
    await for (final entry in temp.list()) {
      if (_owner != null) return;
      if (entry is Directory &&
          entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('conecta2-voice-')) {
        await entry.delete(recursive: true);
      }
    }
  }

  final _recorder = AudioRecorder();
  Directory? _directory;
  bool _closed = false;
  Future<void>? _closing;
  @override
  Future<void> start() async {
    if (_owner != null || _closed) {
      throw StateError('El micrófono ya está en uso.');
    }
    _owner = this;
    try {
      if (!await _recorder.hasPermission() || _closed) {
        throw StateError('Micrófono no disponible.');
      }
      final temp = await getTemporaryDirectory();
      await for (final entry in temp.list()) {
        if (entry is Directory &&
            entry.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('conecta2-voice-')) {
          await entry.delete(recursive: true);
        }
      }
      final dir = await temp.createTemp('conecta2-voice-');
      _directory = dir;
      if (_closed) {
        await dir.delete(recursive: true);
        throw StateError('Grabación cancelada.');
      }
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${dir.path}/speech.wav',
      );
      if (_closed) await _recorder.stop();
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  @override
  Future<String?> stop() => _recorder.stop();
  @override
  Future<void> dispose() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _recorder.dispose();
    } finally {
      final dir = _directory;
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
      _directory = null;
      if (identical(_owner, this)) _owner = null;
    }
  }
}
