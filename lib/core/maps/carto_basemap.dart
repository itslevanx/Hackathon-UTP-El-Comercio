import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import 'carto_tile_cache.dart';

/// No contiene la clave en su representación de diagnóstico.
class CartoConfiguration {
  const CartoConfiguration({this.apiKey = AppConfig.cartoApiKey});
  final String apiKey;
  bool get isConfigured => apiKey.trim().isNotEmpty;
  Uri tileUri(int z, int x, int y) => Uri.https(
    'basemaps.cartocdn.com',
    '/rastertiles/voyager/$z/$x/$y.png',
    {'key': apiKey},
  );
  @override
  String toString() =>
      'CARTO Voyager (${isConfigured ? 'configurado' : 'sin clave'})';
}

class MobileMapIdentity {
  static const channel = MethodChannel('pe.vecinos.app/map_identity');
  static Future<Map<String, String>> headers() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return {};
    }
    try {
      final values = await channel.invokeMapMethod<String, String>('headers');
      return Map<String, String>.from(values ?? const {});
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  static bool isValid(Map<String, String> headers, TargetPlatform platform) {
    if (platform == TargetPlatform.iOS) {
      return (headers['X-Ios-Bundle-Identifier'] ?? '').isNotEmpty;
    }
    if (platform == TargetPlatform.android) {
      return (headers['X-Android-Package'] ?? '').isNotEmpty &&
          RegExp(r'^[A-Fa-f0-9]{40}$')
              .hasMatch(headers['X-Android-Cert'] ?? '');
    }
    return false;
  }
}

LatLng? approximateMapPoint(double? latitude, double? longitude) {
  if (latitude == null ||
      longitude == null ||
      !latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -85.05112878 ||
      latitude > 85.05112878 ||
      longitude < -180 ||
      longitude > 180) {
    return null;
  }
  return LatLng(
    AppConfig.roundPublicCoordinate(latitude),
    AppConfig.roundPublicCoordinate(longitude),
  );
}

/// Un cliente por mapa, con caché local de tiles vistos y sin descargas masivas. Nunca entrega URLs con clave
/// al sistema de diagnósticos de ImageProvider.
class CartoTileProvider extends TileProvider {
  CartoTileProvider({
    required this.configuration,
    required Map<String, String> identity,
    required this.onTileResult,
    this.onTileStatus,
    http.Client? client,
    this.online = true,
    MapTileCache? tileCache,
  }) : _cache = tileCache ?? CartoTileCache.shared,
       _client = client ?? http.Client(),
       _identity = Map.of(identity),
       _cacheIdentity = sha256
           .convert(
             utf8.encode(
               '${configuration.apiKey}|${jsonEncode(Map.fromEntries(identity.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))}',
             ),
           )
           .toString();
  final CartoConfiguration configuration;
  final Map<String, String> _identity;
  final String _cacheIdentity;
  final http.Client _client;
  final MapTileCache _cache;
  final bool online;
  final void Function(bool success) onTileResult;
  final void Function(TileCoordinates tile, bool success)? onTileStatus;
  bool _closed = false;
  int _inFlight = 0;
  final List<Completer<void>> _waiting = [];
  final Set<Completer<void>> _abort = {};
  static final _transparent = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  bool get supportsCancelLoading => true;
  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => _CartoImage(
    this,
    coordinates,
    cancelLoading,
    '$_cacheIdentity:${coordinates.z}/${coordinates.x}/${coordinates.y}',
  );

  Future<Uint8List> bytes(
    TileCoordinates coordinates,
    Future<void> cancel,
  ) async {
    final cacheKey =
        '$_cacheIdentity:${coordinates.z}/${coordinates.x}/${coordinates.y}';
    try {
      final cached = await _cache.read(cacheKey);
      if (cached != null) {
        final codec = await ui.instantiateImageCodec(cached);
        codec.dispose();
        if (!_closed) {
          onTileResult(true);
          onTileStatus?.call(coordinates, true);
        }
        return cached;
      }
    } catch (_) {
      /* La caché no debe impedir el mapa online. */
    }
    if (!online) {
      if (!_closed) {
        onTileResult(false);
        onTileStatus?.call(coordinates, false);
      }
      return _transparent;
    }
    var cancelled = false;
    final abort = Completer<void>();
    unawaited(
      cancel.then((_) {
        cancelled = true;
        if (!abort.isCompleted) abort.complete();
      }),
    );
    if (_inFlight >= 4) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    } else {
      _inFlight++;
    }
    if (_closed || cancelled) {
      _releaseSlot();
      return _transparent;
    }
    _abort.add(abort);
    final timer = Timer(const Duration(seconds: 12), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final request = http.AbortableRequest(
        'GET',
        configuration.tileUri(coordinates.z, coordinates.x, coordinates.y),
        abortTrigger: abort.future,
      );
      request.headers.addAll({
        ..._identity,
        'User-Agent': 'Conecta2/1.0 flutter_map/8.3.2',
      });
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').startsWith('image/')) {
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 12),
        );
        throw const FormatException('Mapa no disponible');
      }
      final data = await response.stream.toBytes().timeout(
        const Duration(seconds: 12),
      );
      // También valida imágenes dañadas sin enviar su URL a los logs de Flutter.
      final codec = await ui.instantiateImageCodec(data);
      codec.dispose();
      try {
        await _cache.write(
          cacheKey,
          data,
          cartoCacheLifetime(response.headers),
        );
      } catch (_) {}
      if (!_closed && !cancelled) {
        onTileResult(true);
        onTileStatus?.call(coordinates, true);
      }
      return data;
    } catch (_) {
      if (!_closed && !cancelled) {
        onTileResult(false);
        onTileStatus?.call(coordinates, false);
      }
      return _transparent;
    } finally {
      timer.cancel();
      _abort.remove(abort);
      _releaseSlot();
    }
  }

  void _releaseSlot() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _inFlight--;
    }
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    for (final abort in _abort) {
      if (!abort.isCompleted) abort.complete();
    }
    for (final waiter in _waiting) {
      waiter.complete();
    }
    _waiting.clear();
    _client.close();
    super.dispose();
  }
}

@immutable
class _CartoImage extends ImageProvider<_CartoImage> {
  const _CartoImage(
    this.provider,
    this.coordinates,
    this.cancel,
    this.cacheKey,
  );
  final CartoTileProvider provider;
  final TileCoordinates coordinates;
  final Future<void> cancel;
  final String cacheKey;
  @override
  Future<_CartoImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    _CartoImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decode(decode),
    scale: 1,
    debugLabel: 'CARTO Voyager',
  );
  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await provider.bytes(coordinates, cancel);
    if (identical(bytes, CartoTileProvider._transparent)) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _CartoImage && other.cacheKey == cacheKey;
  @override
  int get hashCode => cacheKey.hashCode;
  @override
  String toString() => 'CARTO Voyager tile';
}
