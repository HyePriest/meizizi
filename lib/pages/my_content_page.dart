import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'reading_page.dart';

enum MyContent { threads, replies, saved }

class MyContentPage extends StatefulWidget {
  const MyContentPage({super.key, required this.kind});
  final MyContent kind;
  @override
  State<MyContentPage> createState() => _MyContentPageState();
}

class _MyContentPageState extends State<MyContentPage> {
  final _api = TiebaApi();
  final _items = <Json>[];
  late final String _account = AuthStore.instance.activeId;
  int _page = 0;
  bool _busy = false, _more = true;
  String? _error;
  String get _title => switch (widget.kind) {
    MyContent.threads => '我的发帖',
    MyContent.replies => '我的回帖',
    MyContent.saved => '我的收藏',
  };
  @override
  void initState() {
    super.initState();
    _load();
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
      if (_account != AuthStore.instance.activeId) {
        throw const TiebaException('账号已切换，请重新打开此页面');
      }
      final page = reset ? 1 : _page + 1;
      final result = widget.kind == MyContent.saved
          ? await _api.savedThreads(page)
          : await _api.userPosts(
              firstText([
                AuthStore.instance.user['id'],
                AuthStore.instance.user['user_id'],
              ]),
              page,
              replies: widget.kind == MyContent.replies,
            );
      if (!mounted || _account != AuthStore.instance.activeId) return;
      final incoming = objects(
        result.data[widget.kind == MyContent.saved
            ? 'store_thread'
            : 'post_list'],
      );
      setState(() {
        if (reset) _items.clear();
        final seen = _items
            .map(
              (p) =>
                  '${p['thread_id'] ?? p['tid'] ?? p['id']}:${p['post_id'] ?? ''}',
            )
            .toSet();
        _items.addAll(
          incoming.where(
            (p) => seen.add(
              '${p['thread_id'] ?? p['tid'] ?? p['id']}:${p['post_id'] ?? ''}',
            ),
          ),
        );
        _page = page;
        _more = result.data.containsKey('has_more')
            ? flag(result.data['has_more'])
            : incoming.length >= 20;
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
    appBar: AppBar(title: Text(_title)),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          for (final item in _items)
            Card(
              child: ListTile(
                title: Text(
                  firstText([
                    item['title'],
                    object(item['thread'])['title'],
                  ], '查看帖子'),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${threadForumName(item)}吧'),
                    if (widget.kind == MyContent.replies)
                      PostContent(parts: contentParts(item['content'])),
                  ],
                ),
                onTap: () {
                  final tid = firstText([
                    item['thread_id'],
                    item['tid'],
                    object(item['thread'])['id'],
                    item['id'],
                  ]);
                  if (tid.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReadingPage(
                          threadId: tid,
                          title: firstText([item['title']]),
                          forum: threadForumName(item),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          if (_error != null)
            Column(
              children: [
                Text(_error!),
                TextButton(
                  onPressed: () => _load(reset: _page == 0),
                  child: const Text('重试'),
                ),
              ],
            ),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_error == null && _more)
            TextButton(onPressed: _load, child: const Text('加载更多'))
          else if (_error == null && _items.isEmpty)
            const Center(child: Text('暂无内容')),
        ],
      ),
    ),
  );
}
