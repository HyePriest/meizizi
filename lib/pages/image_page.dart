import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ImagePage extends StatefulWidget {
  const ImagePage({super.key, required this.url});
  final String url;
  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  final _transform = TransformationController();
  final _client = http.Client();
  Offset _tap = Offset.zero;
  bool _saving = false;
  @override
  void dispose() {
    _transform.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final response = await _client
          .send(
            http.Request('GET', Uri.parse(widget.url))
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
            .showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
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
      title: const Text('图片'),
      actions: [
        IconButton(
          tooltip: '恢复大小',
          onPressed: () => _transform.value = Matrix4.identity(),
          icon: const Icon(Icons.fit_screen),
        ),
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
    body: LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) => _tap = details.localPosition,
        onDoubleTap: () {
          _transform.value = _transform.value.getMaxScaleOnAxis() > 1.01
              ? Matrix4.identity()
              : (Matrix4.diagonal3Values(3, 3, 1)
                  ..setTranslationRaw(-2 * _tap.dx, -2 * _tap.dy, 0));
        },
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 8,
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
                child: Text(
                  '图片加载失败，请返回重试',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
