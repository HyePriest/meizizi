import 'dart:async';

import 'package:flutter/material.dart';
import '../data/voice_channel.dart';

import '../data/models.dart';

class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.part});
  final Json part;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> with WidgetsBindingObserver {
  static const _channel = VoiceChannel();
  static final ValueNotifier<String> _active = ValueNotifier('');
  final _id = UniqueKey().toString();
  bool _playing = false, _loading = false;
  int _position = 0;
  int _revision = 0;
  bool _canResume = false;
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
      _revision++;
      _canResume = false;
      _timer?.cancel();
      setState(() {
        _playing = false;
        _loading = false;
        _position = 0;
      });
    }
  }

  @override
  void didUpdateWidget(covariant VoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ([
      'voice_md5',
      'voice_url',
      'src',
    ].any((key) => oldWidget.part[key] != widget.part[key])) {
      _revision++;
      _timer?.cancel();
      if (_active.value == _id) {
        unawaited(
          _channel.invokeMethod('stop', {'id': _id}).catchError((_) {}),
        );
        _active.value = '';
      }
      _playing = false;
      _loading = false;
      _canResume = false;
      _position = 0;
      _error = null;
    }
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final revision = ++_revision;
    try {
      if (_playing) {
        _timer?.cancel();
        setState(() => _loading = true);
        await _channel.invokeMethod('pause', {'id': _id});
        if (!mounted || revision != _revision || _active.value != _id) return;
        setState(() {
          _playing = false;
          _loading = false;
        });
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
      final resume = _active.value == _id && _canResume;
      _active.value = _id;
      setState(() {
        _loading = true;
        _error = null;
      });
      await _channel
          .invokeMethod(resume ? 'resume' : 'play', {'url': url, 'id': _id})
          .timeout(const Duration(seconds: 18));
      if (!mounted || revision != _revision || _active.value != _id) return;
      _canResume = true;
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
          if (!mounted || revision != _revision || _active.value != _id) return;
          setState(() {
            _position = number(state?['position']);
            _playing = state?['playing'] == true;
            if (state?['error'] == true) _error = '播放失败，点击重试';
            if (state?['completed'] == true || state?['error'] == true) {
              _canResume = false;
              _position = 0;
            }
          });
          if (!_playing) {
            _timer?.cancel();
          }
        } catch (_) {
          if (!mounted || revision != _revision || _active.value != _id) return;
          _timer?.cancel();
          setState(() {
            _playing = false;
            _canResume = false;
            _error = '播放失败，点击重试';
          });
        }
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      _canResume = false;
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
    _revision++;
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
