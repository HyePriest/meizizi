import '../widgets/app_snack_bar.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ImagePage extends StatefulWidget {
  const ImagePage({super.key, required this.url, this.urls = const []});
  final String url;
  final List<String> urls;
  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  final _client = http.Client();
  late final List<String> _images;
  late final PageController _pages;
  late int _index;
  bool _zoomed = false;
  String get _url => _images[_index];
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _images = (widget.urls.isEmpty ? [widget.url] : widget.urls)
        .toSet()
        .toList();
    _index = _images.indexOf(widget.url).clamp(0, _images.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final url = _url;
    setState(() => _saving = true);
    try {
      final response = await _client
          .send(
            http.Request('GET', Uri.parse(url))
              ..headers['Referer'] = 'https://tieba.baidu.com/',
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('图片下载失败：${response.statusCode}');
      }
      const limit = 32 * 1024 * 1024;
      if ((response.contentLength ?? 0) > limit) {
        throw Exception('图片超过 32 MB，暂时无法保存');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        bytes.add(chunk);
        if (bytes.length > limit) throw Exception('图片超过 32 MB，暂时无法保存');
      }
      final content = bytes.takeBytes();
      // Detect the actual file format; CDN URLs often have no extension.
      final mime =
          content.length >= 12 && content[0] == 0x89 && content[1] == 0x50
          ? 'image/png'
          : content.length >= 6 && content[0] == 0x47 && content[1] == 0x49
          ? 'image/gif'
          : content.length >= 12 && content[0] == 0x52 && content[8] == 0x57
          ? 'image/webp'
          : content.length >= 3 && content[0] == 0xff && content[1] == 0xd8
          ? 'image/jpeg'
          : '';
      if (mime.isEmpty) throw Exception('服务器未返回可保存的图片');
      final extension = mime == 'image/jpeg' ? 'jpg' : mime.split('/').last;
      final saved = await const MethodChannel('com.jknl.tieba/session')
          .invokeMethod<bool>('saveImage', {
            'bytes': content,
            'mime': mime,
            'name': 'tieba_${DateTime.now().millisecondsSinceEpoch}.$extension',
          });
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('图片已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(AppSnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} / ${_images.length}'),
      actions: [
        IconButton(
          tooltip: '下载图片',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
        ),
      ],
    ),
    body: PageView.builder(
      controller: _pages,
      itemCount: _images.length,
      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (index) => setState(() {
        _index = index;
        _zoomed = false;
      }),
      itemBuilder: (_, index) => _GalleryImage(
        key: ValueKey(_images[index]),
        url: _images[index],
        onZoom: (value) {
          if (mounted && index == _index && value != _zoomed)
            setState(() => _zoomed = value);
        },
      ),
    ),
  );
}

class _GalleryImage extends StatefulWidget {
  const _GalleryImage({super.key, required this.url, required this.onZoom});
  final String url;
  final ValueChanged<bool> onZoom;
  @override
  State<_GalleryImage> createState() => _GalleryImageState();
}

class _GalleryImageState extends State<_GalleryImage> {
  final _transform = TransformationController();
  Offset _tap = Offset.zero;
  @override
  void initState() {
    super.initState();
    _transform.addListener(
      () => widget.onZoom(_transform.value.getMaxScaleOnAxis() > 1.01),
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => _tap = details.localPosition,
      onDoubleTap: () =>
          _transform.value = _transform.value.getMaxScaleOnAxis() > 1.01
          ? Matrix4.identity()
          : (Matrix4.diagonal3Values(3, 3, 1)
              ..setTranslationRaw(-2 * _tap.dx, -2 * _tap.dy, 0)),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 8,
        panEnabled: _transform.value.getMaxScaleOnAxis() > 1.01,
        onInteractionEnd: (_) {
          if (mounted) setState(() {});
        },
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Image.network(
            widget.url,
            headers: const {'Referer': 'https://tieba.baidu.com/'},
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) => const Center(
              child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    ),
  );
}
