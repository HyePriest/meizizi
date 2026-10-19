import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';

class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.part});
  final Json part;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.jknl.tieba/voice');
  static final ValueNotifier<String> _active = ValueNotifier('');
  final _id = UniqueKey().toString();
  bool _playing = false, _loading = false;
  int _position = 0;
  Timer? _timer;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active.addListener(_changed);
  }

  void _changed() {
    if (_active.value != _id && mounted) {
      _timer?.cancel();
      setState(() {
        _playing = false;
        _loading = false;
        _position = 0;
      });
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    try {
      if (_playing) {
        await _channel.invokeMethod('pause', {'id': _id});
        if (mounted) setState(() => _playing = false);
        _timer?.cancel();
        return;
      }
      final md5 = firstText([widget.part['voice_md5']]);
      final direct = firstText([widget.part['voice_url'], widget.part['src']]);
      final url = md5.isNotEmpty
          ? Uri.https('c.tieba.baidu.com', '/c/p/voice', {
              'voice_md5': md5,
            }).toString()
          : direct;
      if (Uri.tryParse(url)?.scheme != 'https') throw const FormatException();
      final resume = _active.value == _id && _position > 0;
      _active.value = _id;
      setState(() {
        _loading = true;
        _error = null;
      });
      await _channel
          .invokeMethod(resume ? 'resume' : 'play', {'url': url, 'id': _id})
          .timeout(const Duration(seconds: 18));
      if (!mounted || _active.value != _id) return;
      setState(() {
        _playing = true;
        _loading = false;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          final state = await _channel.invokeMapMethod<String, dynamic>(
            'state',
            {'id': _id},
          );
          if (!mounted || _active.value != _id) return;
          setState(() {
            _position = number(state?['position']);
            _playing = state?['playing'] == true;
            if (state?['error'] == true) _error = '播放失败，点击重试';
          });
          if (!_playing) {
            _timer?.cancel();
            _position = 0;
          }
        } catch (_) {
          _timer?.cancel();
        }
      });
    } catch (_) {
      unawaited(_channel.invokeMethod('stop', {'id': _id}).catchError((_) {}));
      if (mounted && _active.value == _id)
        setState(() {
          _loading = false;
          _playing = false;
          _position = 0;
          _error = '语音加载失败，点击重试';
        });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _active.value == _id) {
      unawaited(_channel.invokeMethod('stop', {'id': _id}).catchError((_) {}));
      _active.value = '';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active.removeListener(_changed);
    _timer?.cancel();
    if (_active.value == _id)
      unawaited(_channel.invokeMethod('stop', {'id': _id}).catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (number(widget.part['during_time']) / 1000).ceil();
    return OutlinedButton.icon(
      onPressed: _loading ? null : _toggle,
      icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      label: Text(
        _error ??
            (_loading
                ? '正在加载语音…'
                : '${_playing ? '${_position ~/ 1000} / ' : ''}${seconds > 0 ? '${seconds}秒' : '语音'}'),
      ),
    );
  }
}
