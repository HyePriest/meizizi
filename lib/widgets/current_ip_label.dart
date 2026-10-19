import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';

/// The floor API can omit the post-time IP. This is explicitly the author's
/// current public profile location, never presented as the post-time location.
class CurrentIpLabel extends StatefulWidget {
  const CurrentIpLabel({super.key, required this.user});
  final Json user;
  @override
  State<CurrentIpLabel> createState() => _CurrentIpLabelState();
}

class _CurrentIpLabelState extends State<CurrentIpLabel> {
  static final _cache = <String, ({DateTime time, Future<String> value})>{};
  static final _lanes = [Future<void>.value(), Future<void>.value()];
  static int _nextLane = 0;
  late Future<String> _value;

  Future<String> _load() async {
    // Offscreen rows that disappear during a quick fling do not start requests.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return '';
    final account = AuthStore.instance.activeId;
    final key = '$account:${userKey(widget.user)}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 10))
      return cached.value;
    final user = widget.user;
    final lane = _nextLane++ % 2;
    final value = _lanes[lane].then((_) async {
      if (account != AuthStore.instance.activeId) {
        _cache.remove(key);
        return '';
      }
      final api = TiebaApi();
      try {
        return await api.currentUserIp(user);
      } catch (_) {
        _cache.remove(key);
        return '';
      } finally {
        api.close();
      }
    });
    _lanes[lane] = value.then<void>((_) {});
    if (_cache.length >= 256) _cache.remove(_cache.keys.first);
    _cache[key] = (time: DateTime.now(), value: value);
    return value;
  }

  @override
  void initState() {
    super.initState();
    _value = _load();
  }

  @override
  void didUpdateWidget(CurrentIpLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (userKey(oldWidget.user) != userKey(widget.user)) _value = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _value,
    builder: (context, result) => Text(
      result.hasData
          ? (result.data!.isEmpty ? 'IP 未提供' : '当前 IP：${result.data}')
          : '当前 IP：…',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        height: 1.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
