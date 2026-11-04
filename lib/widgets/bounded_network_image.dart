import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../data/image_bytes.dart';

const tiebaImageHeaders = {
  'Referer': 'https://tieba.baidu.com/',
  'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36',
};

final _pendingDownloads = <String, _ImageDownload>{};

class _ImageDownload {
  final cancelled = Completer<void>();
  late final Future<Uint8List> bytes;
  int readers = 0;
}

Future<Uint8List> _sharedImageBytes(String url, Future<void> cancelled) async {
  final request = _pendingDownloads.putIfAbsent(url, () {
    final entry = _ImageDownload();
    entry.bytes = downloadImageBytes(url, cancelled: entry.cancelled.future);
    return entry;
  });
  request.readers++;
  try {
    return await Future.any([
      request.bytes,
      cancelled.then<Uint8List>(
        (_) => throw StateError('Image request cancelled'),
      ),
    ]);
  } finally {
    request.readers--;
    if (request.readers == 0) {
      if (identical(_pendingDownloads[url], request))
        _pendingDownloads.remove(url);
      request.cancelled.complete();
    }
  }
}

/// A timeout must also close the socket, otherwise a retry can join the same
/// pending image-cache entry or leave downloads running in the background.
Future<Uint8List> downloadImageBytes(
  String url, {
  void Function(int, int?)? onProgress,
  Duration idleTimeout = const Duration(seconds: 2),
  Duration totalTimeout = const Duration(seconds: 60),
  Future<void>? cancelled,
}) async {
  final client = HttpClient()..autoUncompress = false;
  final expired = Completer<Uint8List>();
  var active = true;
  Timer? idle;
  void expire() {
    if (!expired.isCompleted) {
      expired.completeError(
        TimeoutException('Image download timed out', idleTimeout),
      );
      client.close(force: true);
    }
  }

  void watch() {
    if (!active) return;
    idle?.cancel();
    idle = Timer(idleTimeout, expire);
  }

  Future<Uint8List> read() async {
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    tiebaImageHeaders.forEach(
      (name, value) => request.headers.add(name, value),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      // Do not wait for a broken/error response body before trying a mirror.
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    watch();
    final bytes = await consolidateHttpClientResponseBytes(
      response,
      onBytesReceived: (received, total) {
        watch();
        onProgress?.call(received, total);
      },
    );
    if (bytes.isEmpty) throw StateError('Empty image response');
    return bytes;
  }

  watch();
  final deadline = Timer(totalTimeout, expire);
  cancelled?.then((_) {
    if (active && !expired.isCompleted) {
      expired.completeError(StateError('Image request cancelled'));
      client.close(force: true);
    }
  });
  try {
    return await Future.any([read(), expired.future]);
  } finally {
    active = false;
    idle?.cancel();
    deadline.cancel();
    client.close(force: true);
  }
}

@immutable
class BoundedNetworkImage extends ImageProvider<BoundedNetworkImage> {
  const BoundedNetworkImage(this.url, {this.alternate});
  final String url;
  final String? alternate;

  @override
  Future<BoundedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    BoundedNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode, chunks),
      scale: 1,
      chunkEvents: chunks.stream,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(
    BoundedNetworkImage key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    // ResizeImage has separate decoded entries for list and post sizes, but
    // both can decode the same already downloaded bytes without another GET.
    for (final source in [url, if (alternate != null) alternate!]) {
      final bytes = await ImageBytes.read(source);
      if (bytes == null) continue;
      try {
        final codec = await decode(
          await ui.ImmutableBuffer.fromUint8List(bytes),
        );
        unawaited(chunks.close());
        return codec;
      } catch (_) {
        // An invalid cache entry may be replaced by a fresh successful load.
      }
    }
    final result = Completer<ui.Codec>();
    final cancelled = Completer<void>();
    final hasAlternate = alternate != null && alternate != url;
    var failures = 0;
    var alternateStarted = false;
    Timer? hedge;
    late void Function() startAlternate;

    Future<void> attempt(String source) async {
      try {
        final bytes = await _sharedImageBytes(source, cancelled.future);
        if (result.isCompleted) return;
        final codec = await decode(
          await ui.ImmutableBuffer.fromUint8List(bytes),
        );
        ImageBytes.remember(source, bytes);
        if (result.isCompleted) {
          codec.dispose();
        } else {
          result.complete(codec);
        }
      } catch (error, stack) {
        if (result.isCompleted) return;
        failures++;
        if (failures >= (hasAlternate ? 2 : 1)) {
          result.completeError(error, stack);
        } else {
          startAlternate();
        }
      }
    }

    startAlternate = () {
      if (!hasAlternate || alternateStarted || result.isCompleted) return;
      alternateStarted = true;
      unawaited(attempt(alternate!));
    };
    // Fast images use one request. A slow source does not hold up its mirror;
    // keep the original alive until either source produces a decodable image.
    if (hasAlternate) {
      hedge = Timer(const Duration(milliseconds: 300), startAlternate);
    }
    unawaited(attempt(url));
    try {
      return await result.future;
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      hedge?.cancel();
      cancelled.complete();
      unawaited(chunks.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BoundedNetworkImage &&
      other.url == url &&
      other.alternate == alternate;
  @override
  int get hashCode => Object.hash(BoundedNetworkImage, url, alternate);
}
