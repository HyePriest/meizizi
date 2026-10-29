import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/image_bytes.dart';
import 'bounded_network_image.dart';

List<String> imageSources(Iterable<dynamic> sources) {
  final urls = sources
      .map(httpsImage)
      .where((url) => url.isNotEmpty)
      .toSet()
      .toList();
  for (final url in List.of(urls)) {
    final uri = Uri.parse(url);
    if (!const [
      'tiebapic.baidu.com',
      'imgsrc.baidu.com',
      'imgsa.baidu.com',
    ].contains(uri.host))
      continue;
    final file = RegExp(
      r'[a-fA-F0-9]{32,40}\.(?:jpg|jpeg|png|gif|webp)',
      caseSensitive: false,
    ).firstMatch(uri.path)?[0];
    if (file == null) continue;
    for (final host in ['tiebapic.baidu.com', 'imgsrc.baidu.com']) {
      final alternate = 'https://$host/forum/pic/item/$file';
      if (!urls.contains(alternate)) urls.add(alternate);
    }
  }
  return urls.take(5).toList();
}

class ReliableImage extends StatefulWidget {
  const ReliableImage({
    super.key,
    required this.urls,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.cacheWidth,
    this.fallback,
    this.useCachedPreview = true,
  });
  final List<String> urls;
  final double? width, height;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? fallback;

  /// Whether another cached size may be shown while the requested image loads.
  final bool useCachedPreview;
  @override
  State<ReliableImage> createState() => _ReliableImageState();
}

class _ReliableImageState extends State<ReliableImage> {
  late List<String> _urls;
  int _attempt = 0;
  int _generation = 0;

  static final _preferred = <String, ({String url, DateTime time})>{};
  Timer? _retry;
  bool _finished = false;
  bool _failed = false;
  Uint8List? _preview;
  ImageProvider? _cachedProvider;
  ImageProvider get _provider {
    if (_cachedProvider != null) return _cachedProvider!;
    final index = _attempt % _urls.length;
    final primary = _urls[index];
    final remaining = [..._urls.skip(index + 1), ..._urls.take(index)];
    // Prefer another CDN host over another size on the same stalled host.
    final alternate =
        remaining
            .where((url) => Uri.parse(url).host != Uri.parse(primary).host)
            .firstOrNull ??
        remaining.firstOrNull;
    return _cachedProvider = ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      BoundedNetworkImage(primary, alternate: alternate),
    );
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _cachedProvider = null;
    _generation++;
    _retry?.cancel();
    _retry = null;

    _urls = imageSources(widget.urls);
    _preview = widget.useCachedPreview ? ImageBytes.preview(_urls) : null;
    final preferred = _preferred[widget.urls.join('|')];
    if (preferred != null &&
        DateTime.now().difference(preferred.time) <
            const Duration(minutes: 10) &&
        _urls.remove(preferred.url)) {
      _urls.insert(0, preferred.url);
    }

    _attempt = 0;
    _finished = false;
    _failed = false;
  }

  void _next() {
    if (!mounted || _finished || _retry != null) return;

    final generation = _generation;
    _retry = Timer(
      Duration(milliseconds: _attempt + 1 == _urls.length ? 800 : 120),
      () {
        if (!mounted || _finished || generation != _generation) return;
        if (_attempt + 1 >= _urls.length * 2) {
          setState(() {
            _retry = null;
            _finished = _failed = true;
          });
          return;
        }
        setState(() {
          _retry = null;
          _attempt++;
          _cachedProvider = null;
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant ReliableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls) ||
        oldWidget.useCachedPreview != widget.useCachedPreview) {
      _reset();
    }
    if (oldWidget.cacheWidth != widget.cacheWidth) _cachedProvider = null;
  }

  @override
  void dispose() {
    _retry?.cancel();

    super.dispose();
  }

  Widget _previewImage() => Image.memory(
    _preview!,
    width: widget.width,
    height: widget.height,
    fit: widget.fit,
    cacheWidth: widget.cacheWidth,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => widget.fallback ?? const SizedBox.shrink(),
  );

  Widget _failure() => GestureDetector(
    onTap: () {
      setState(_reset);
    },
    child: _preview != null
        ? _previewImage()
        : widget.fallback ??
              SizedBox(
                width: widget.width,
                height: widget.height ?? 80,
                child: const Center(child: Icon(Icons.refresh, size: 22)),
              ),
  );

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty || _failed) return _failure();
    return Image(
      key: ValueKey('$_generation:$_attempt:${_urls[_attempt % _urls.length]}'),
      image: _provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      frameBuilder: (_, child, frame, synchronous) {
        if (!_finished && (synchronous || frame != null)) {
          _retry?.cancel();
          _retry = null;
          _finished = true;
          if (_preferred.length >= 128)
            _preferred.remove(_preferred.keys.first);
          _preferred[widget.urls.join('|')] = (
            url: _urls[_attempt % _urls.length],
            time: DateTime.now(),
          );
        }
        if (synchronous || frame != null) return child;
        if (_preview != null) return _previewImage();
        return SizedBox(
          width: widget.width,
          height: widget.height ?? 80,
          child: const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) {
        _next();
        if (_preview != null) return _previewImage();
        return SizedBox(
          width: widget.width,
          height: widget.height ?? 80,
          child: const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
