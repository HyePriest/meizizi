import 'platform_session.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Encoded bytes are shared across decode sizes. A preview never substitutes
/// for the requested full-resolution bytes in the exact-URL cache.
class ImageBytes {
  static final _memory = LinkedHashMap<String, Uint8List>();
  static final _previews = <String, String>{};
  static final _pendingReads = <String, Future<Uint8List?>>{};
  static final _imageIdentity = RegExp(
    r'([a-fA-F0-9]{32,40})\.(?:jpg|jpeg|png|webp|gif)(?:$|/)',
    caseSensitive: false,
  );
  static int _size = 0;
  static Future<Directory?>? _directory;
  static Future<void> _writes = Future.value();
  static final _pendingDisk = <String>{};
  static int _queuedBytes = 0, _bytesSinceTrim = 0;
  static DateTime? _lastTrim;
  static const _memoryLimit = 48 * 1024 * 1024;
  static const _diskLimit = 192 * 1024 * 1024;

  static String _identity(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const [
          'tiebapic.baidu.com',
          'imgsrc.baidu.com',
          'imgsa.baidu.com',
        ].contains(uri.host))
      return url;
    final file = _imageIdentity.firstMatch(uri.path);
    return file == null ? url : 'tieba:${file[1]!.toLowerCase()}';
  }

  static Uint8List? peek(String url) {
    final bytes = _memory.remove(url);
    if (bytes != null) _memory[url] = bytes;
    return bytes;
  }

  static Uint8List? preview(Iterable<String> urls) {
    for (final url in urls) {
      final bytes = peek(url) ?? peek(_previews[_identity(url)] ?? '');
      if (bytes != null) return bytes;
    }
    return null;
  }

  static Future<Directory?> _cacheDirectory() => _directory ??= (() async {
    try {
      final path = await const PlatformSession()
          .invokeMethod<String>('imageCacheDirectory');
      if (path == null) return null;
      return await Directory(path).create(recursive: true);
    } catch (_) {
      return null;
    }
  })();

  static String _name(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  static void _keep(String url, Uint8List bytes) {
    if (bytes.length > _memoryLimit) return;
    _size -= _memory.remove(url)?.length ?? 0;
    _memory[url] = bytes;
    _previews[_identity(url)] = url;
    _size += bytes.length;
    while (_size > _memoryLimit || _memory.length > 256) {
      final oldest = _memory.keys.first;
      _size -= _memory.remove(oldest)!.length;
      final identity = _identity(oldest);
      if (_previews[identity] == oldest) _previews.remove(identity);
    }
  }

  static Future<Uint8List?> read(String url) {
    final memory = peek(url);
    if (memory != null) return Future.value(memory);
    // Different decode sizes share one disk read and one retained byte buffer.
    return _pendingReads.putIfAbsent(url, () async {
      try {
        return await _readDisk(url);
      } finally {
        _pendingReads.remove(url);
      }
    });
  }

  static Future<Uint8List?> _readDisk(String url) async {
    try {
      final directory = await _cacheDirectory();
      if (directory == null) return null;
      final file = File('${directory.path}/${_name(url)}');
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      _keep(url, bytes);
      unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Only called after the decoder has accepted the downloaded content.
  static void remember(String url, Uint8List bytes) {
    final alreadyCached = identical(peek(url), bytes);
    if (alreadyCached) return;
    _keep(url, bytes);
    // Decoding the same bytes at multiple sizes must not enqueue duplicate IO.
    // Disk caching is optional; bound retained buffers during rapid scrolling.
    if (_pendingDisk.contains(url) ||
        _queuedBytes + bytes.length > 32 * 1024 * 1024)
      return;
    _pendingDisk.add(url);
    _queuedBytes += bytes.length;
    _writes = _writes.then((_) async {
      try {
        final directory = await _cacheDirectory();
        if (directory == null || bytes.length > _diskLimit) return;
        final file = File('${directory.path}/${_name(url)}');
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes);
        await temporary.rename(file.path);
        _bytesSinceTrim += bytes.length;
        final now = DateTime.now();
        if (_lastTrim != null &&
            _bytesSinceTrim < 8 * 1024 * 1024 &&
            now.difference(_lastTrim!) < const Duration(minutes: 1))
          return;
        final files = <({File file, FileStat stat})>[];
        var total = 0;
        await for (final entry in directory.list()) {
          if (entry is! File) continue;
          final stat = await entry.stat();
          total += stat.size;
          files.add((file: entry, stat: stat));
        }
        files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
        for (final entry in files) {
          if (total <= _diskLimit) break;
          await entry.file.delete();
          total -= entry.stat.size;
        }
        _lastTrim = now;
        _bytesSinceTrim = 0;
      } catch (_) {
        // Storage pressure or OS cache cleanup must not break image display.
      } finally {
        _pendingDisk.remove(url);
        _queuedBytes -= bytes.length;
      }
    });
  }
}
