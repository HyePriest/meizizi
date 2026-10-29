import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_webview.dart';

/// Desktop system operations; Android retains its original native channel.
class PlatformSession {
  const PlatformSession();
  static const _android = MethodChannel('com.jknl.tieba/session');
  static const imageTypes = XTypeGroup(
    label: '图片',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
  );

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (!Platform.isWindows) return _android.invokeMethod<T>(method, arguments);
    final args = (arguments as Map?) ?? const {};
    dynamic result;
    switch (method) {
      case 'appVersion':
        result = await _android.invokeMethod<String>('appVersion');
      case 'getBaiduCookies':
        result = await DesktopWebSession.baiduCookies();
      case 'clearBaiduCookies':
        await DesktopWebSession.cookies.deleteAllCookies();
      case 'imageCacheDirectory':
        final root = await getApplicationCacheDirectory();
        result = '${root.path}/images';
      case 'saveImage':
      case 'shareImage':
        final bytes = args['bytes'] as Uint8List;
        final name =
            args['name'] as String? ??
            'meizizi_${DateTime.now().millisecondsSinceEpoch}.png';
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [
            XTypeGroup(label: '图片', extensions: [name.split('.').last]),
          ],
        );
        if (location != null) {
          await XFile.fromData(bytes).saveTo(location.path);
          result = true;
        } else {
          result = false;
        }
        if (method == 'shareImage') result = null;
      case 'shareText':
        await Clipboard.setData(ClipboardData(text: '${args['text'] ?? ''}'));
      case 'pickReplyImages':
        final files = await openFiles(acceptedTypeGroups: [imageTypes]);
        if (files.length > 9) {
          throw PlatformException(
            code: 'TOO_MANY_IMAGES',
            message: '每次最多选择 9 张图片',
          );
        }
        final images = <Map<String, dynamic>>[];
        for (final file in files) {
          if (await file.length() > 20 * 1024 * 1024) {
            throw PlatformException(
              code: 'IMAGE_TOO_LARGE',
              message: '请选择小于 20 MB 的图片',
            );
          }
          var bytes = await file.readAsBytes();
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            final extension = file.name.split('.').last.toLowerCase();
            if (['jpg', 'jpeg', 'png', 'gif'].contains(extension) &&
                descriptor.width <= 4096 &&
                descriptor.height <= 4096) {
              images.add({
                'bytes': bytes,
                'width': descriptor.width,
                'height': descriptor.height,
                'mime': 'image/${extension == 'jpg' ? 'jpeg' : extension}',
              });
              continue;
            }
            final longest = descriptor.width > descriptor.height
                ? descriptor.width
                : descriptor.height;
            final codec = await descriptor.instantiateCodec(
              targetWidth: longest > 4096
                  ? (descriptor.width * 4096 / longest).round().clamp(1, 4096)
                  : null,
            );
            try {
              final frame = await codec.getNextFrame();
              try {
                final png = await frame.image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (png == null) throw const FormatException('图片无法读取');
                bytes = png.buffer.asUint8List(
                  png.offsetInBytes,
                  png.lengthInBytes,
                );
                images.add({
                  'bytes': bytes,
                  'width': frame.image.width,
                  'height': frame.image.height,
                  'mime': 'image/png',
                });
              } finally {
                frame.image.dispose();
              }
            } finally {
              codec.dispose();
            }
          } finally {
            descriptor.dispose();
            buffer.dispose();
          }
        }
        result = images;
      case 'openUpdateLink':
        final uri = Uri.parse('${args['url']}');
        if (uri.scheme != 'https' ||
            uri.host != 'github.com' ||
            !(uri.path == '/HyePriest/meizizi' ||
                uri.path.startsWith('/HyePriest/meizizi/'))) {
          throw PlatformException(code: 'INVALID_URL', message: '项目地址无效');
        }
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw PlatformException(code: 'OPEN_FAILED', message: '无法打开浏览器');
        }
      case 'openOfficialTieba':
        if (!await launchUrl(
          Uri.parse('https://tieba.baidu.com/im/pcmsg'),
          mode: LaunchMode.externalApplication,
        )) {
          throw PlatformException(code: 'OPEN_FAILED', message: '无法打开浏览器');
        }
      default:
        throw MissingPluginException('Windows does not implement $method');
    }
    return result as T?;
  }

  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    dynamic arguments,
  ]) async {
    final result = await invokeMethod<dynamic>(method, arguments);
    return result == null ? null : Map<K, V>.from(result as Map);
  }

  Future<List<T>?> invokeListMethod<T>(
    String method, [
    dynamic arguments,
  ]) async {
    final result = await invokeMethod<dynamic>(method, arguments);
    return result == null ? null : List<T>.from(result as List);
  }
}
