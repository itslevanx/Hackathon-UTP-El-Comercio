import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class VoiceModelStore {
  VoiceModelStore({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  static const bytes = 59707625;
  static const digest =
      '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898';
  static final uri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base-q5_1.bin',
  );
  http.Client? _download;
  bool _cancelled = false;
  Future<File> get file async => File(
    '${(await getApplicationSupportDirectory()).path}/voice_models/ggml-base-q5_1.bin',
  );
  Future<String?> readyPath() async {
    final model = await file;
    if (!await model.exists() || await model.length() != bytes) return null;
    // Full integrity check also runs after restart, outside the UI isolate in crypto's streamed IO.
    if (await _hashFile(model.path) != digest) {
      return null;
    }
    return model.path;
  }

  Future<String> download(void Function(double) progress) async {
    if (_download != null) throw StateError('Ya hay una descarga en curso.');
    _cancelled = false;
    final client = _clientFactory();
    _download = client;
    File? partial;
    IOSink? sink;
    try {
      final model = await file;
      partial = File('${model.path}.part');
      await model.parent.create(recursive: true);
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('No se pudo descargar el modelo.');
      }
      sink = partial.openWrite();
      var total = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelled) throw StateError('Descarga cancelada.');
        total += chunk.length;
        if (total > bytes) throw StateError('Tamaño de modelo inválido.');
        sink.add(chunk);
        progress(total / bytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total != bytes || await _hashFile(partial.path) != digest) {
        throw StateError('El modelo no pasó la verificación de integridad.');
      }
      if (_cancelled) throw StateError('Descarga cancelada.');
      await partial.rename(model.path);
      return model.path;
    } finally {
      await sink?.close();
      client.close();
      _download = null;
      if (partial != null && await partial.exists()) await partial.delete();
    }
  }

  void cancelDownload() {
    _cancelled = true;
    _download?.close();
  }
}

Future<String> _hashFile(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);
