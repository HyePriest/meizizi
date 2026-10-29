import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// One audio owner, matching the existing single-playing-voice contract.
class VoiceChannel {
  const VoiceChannel();
  static const _android = MethodChannel('com.jknl.tieba/voice');
  static Player? _player;
  static String _identity = '';
  static String? _error;

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    if (!Platform.isWindows) return _android.invokeMethod<T>(method, arguments);
    final args = (arguments as Map?) ?? const {};
    final id = '${args['id'] ?? ''}';
    if (method != 'play' && id != _identity) return null;
    final player = _player ??= (() {
      final value = Player();
      value.stream.error.listen((error) => _error = error);
      return value;
    })();
    switch (method) {
      case 'play':
        _identity = id;
        _error = null;
        await player.open(Media('${args['url']}'));
      case 'pause':
        await player.pause();
      case 'resume':
        await player.play();
      case 'stop':
        await player.stop();
        _identity = '';
      default:
        throw MissingPluginException('Unknown audio command $method');
    }
    return null;
  }

  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    dynamic arguments,
  ]) async {
    if (!Platform.isWindows) {
      return _android.invokeMapMethod<K, V>(method, arguments);
    }
    final state = _player?.state;
    final active = (arguments as Map?)?['id'] == _identity;
    return Map<K, V>.from({
      'playing': active && (state?.playing ?? false),
      'position': active ? state?.position.inMilliseconds ?? 0 : 0,
      'completed': active && (state?.completed ?? false),
      'error': active && _error != null,
    });
  }
}
