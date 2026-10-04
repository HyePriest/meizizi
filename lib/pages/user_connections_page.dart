import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/post_widgets.dart';
import 'reading_page.dart';
import 'user_page.dart';

enum UserConnections { follows, fans, forums }

class UserConnectionsPage extends StatefulWidget {
  const UserConnectionsPage({super.key, required this.uid, required this.kind});
  final String uid;
  final UserConnections kind;
  @override
  State<UserConnectionsPage> createState() => _UserConnectionsPageState();
}

class _UserConnectionsPageState extends State<UserConnectionsPage> {
  final _api = TiebaApi();
  final List<Json> _items = [];
  bool _busy = false, _more = true;
  int _page = 0;
  String? _error;
  bool get _forums => widget.kind == UserConnections.forums;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = _forums
          ? await _api.userForums(widget.uid, page)
          : await _api.userFollows(
              widget.uid,
              page,
              fans: widget.kind == UserConnections.fans,
            );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        final ids = _items
            .map((v) => _forums ? forumName(v) : userKey(v))
            .toSet();
        _items.addAll(
          result.items.where(
            (v) => ids.add(_forums ? forumName(v) : userKey(v)),
          ),
        );
        _page = page;
        _more = result.hasMore && result.items.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is TiebaException ? e.message : '加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(switch (widget.kind) {
        UserConnections.follows => '关注的人',
        UserConnections.fans => '粉丝',
        UserConnections.forums => '关注的吧',
      }),
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index < _items.length) {
            final item = _items[index];
            if (_forums) {
              final name = forumName(item);
              final level = number(item['level_id']);
              return ListTile(
                leading: ForumAvatar(forum: item),
                title: Text('$name吧'),
                subtitle: level > 0 ? Text('等级 $level') : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingPage(forum: name),
                  ),
                ),
              );
            }
            return ListTile(
              leading: UserAvatar(user: item),
              title: Text(author(item)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openUser(context, item),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_error != null) ...[
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => _load(reset: _items.isEmpty),
                          child: const Text('重试'),
                        ),
                      ] else if (_more)
                        TextButton(onPressed: _load, child: const Text('加载更多'))
                      else
                        Text(
                          _items.isEmpty ? '暂无公开内容，对方可能设置了隐私限制' : '已经到底了',
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
  );
}
