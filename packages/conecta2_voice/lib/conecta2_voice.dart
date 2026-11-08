import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

DynamicLibrary _library() => Platform.isAndroid
    ? DynamicLibrary.open('libconecta2_voice.so')
    : DynamicLibrary.process();

/// Native calls never receive network clients. Each inference owns its context
/// and frees it before returning. Cancellation is scoped to the native token.
class LocalWhisper {
  int? _token;
  Future<String>? _pending;
  Future<String> transcribe(String model, String audio) async {
    if (_pending != null) {
      throw StateError('Ya hay una transcripción en curso.');
    }
    final lib = _library();
    final token = lib.lookupFunction<Int32 Function(), int Function()>(
      'conecta_voice_begin',
    )();
    if (token < 0) throw StateError('El motor de voz está ocupado.');
    _token = token;
    try {
      return await (_pending = Isolate.run(
        () => _transcribe((token, model, audio)),
      ));
    } finally {
      lib.lookupFunction<Void Function(Int32), void Function(int)>(
        'conecta_voice_release',
      )(token);
      _pending = null;
      _token = null;
    }
  }

  Future<void> cancel() async {
    final token = _token;
    if (token != null) {
      _library().lookupFunction<Void Function(Int32), void Function(int)>(
        'conecta_voice_cancel',
      )(token);
    }
    try {
      await _pending;
    } catch (_) {
      /* Caller owns the error. */
    }
  }
}

String _transcribe((int, String, String) request) {
  final lib = _library();
  final model = request.$2.toNativeUtf8();
  final audio = request.$3.toNativeUtf8();
  final output = calloc<Pointer<Utf8>>();
  try {
    final code = lib
        .lookupFunction<
          Int32 Function(
            Int32,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            int,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Pointer<Utf8>>,
          )
        >('conecta_voice_transcribe')(request.$1, model, audio, output);
    if (code == -2) throw const VoiceCancelled();
    if (code != 0) {
      throw StateError('No se pudo procesar el audio local ($code).');
    }
    return output.value == nullptr ? '' : output.value.toDartString().trim();
  } finally {
    if (output.value != nullptr) {
      lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('conecta_voice_free')(output.value);
    }
    calloc.free(output);
    malloc.free(model);
    malloc.free(audio);
  }
}

class VoiceCancelled implements Exception {
  const VoiceCancelled();
}
