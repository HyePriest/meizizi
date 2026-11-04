import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import '../widgets/thread_thumbnails.dart';
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
  bool _busy = false, _more = true, _retryReset = true;
  String? _error;
  String get _title => switch (widget.kind) {
    MyContent.threads => '发帖记录',
    MyContent.replies => '回帖记录',
    MyContent.saved => '收藏记录',
  };
  String _threadTitle(Json item) {
    final title = plainText(
      firstText([
        item['thread_title'],
        object(item['thread'])['title'],
        item['title'],
      ]),
    ).trim();
    final cleaned = widget.kind == MyContent.replies
        ? title.replaceFirst(RegExp(r'^(?:(?:回复帖子|回复)\s*[:：]\s*)+'), '').trim()
        : title;
    return cleaned.isEmpty ? '查看帖子' : cleaned;
  }

  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (!mounted || _account == AuthStore.instance.activeId) return;
    setState(() {
      _items.clear();
      _more = false;
      _error = '账号已切换，请重新打开此页面';
    });
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    _retryReset = reset;
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
      if (mounted && _account == AuthStore.instance.activeId) {
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
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index < _items.length) {
            final item = _items[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
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
                          title: _threadTitle(item),
                          forum: threadForumName(item),
                          targetPostId:
                              widget.kind == MyContent.replies &&
                                  number(item['post_id']) > 0
                              ? '${item['post_id']}'
                              : null,
                        ),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.kind == MyContent.replies) ...[
                        if (contentParts(item['content']).isNotEmpty)
                          PostContent(
                            parts: contentParts(item['content']),
                            openImages: false,
                          )
                        else
                          Text(
                            flag(item['is_post_deleted'])
                                ? '这条回帖已删除'
                                : '这条回帖的正文暂不可用',
                          ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _threadTitle(item),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ] else ...[
                        Text(
                          firstText([
                            item['title'],
                            object(item['thread'])['title'],
                          ], '查看帖子'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (widget.kind == MyContent.threads)
                          ThreadThumbnails(
                            thread: {...object(item['thread']), ...item},
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (threadForumName(item).isNotEmpty)
                            '${threadForumName(item)}吧',
                          if (number(item['create_time'] ?? item['time']) > 0)
                            commentTime(item['create_time'] ?? item['time']),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              if (_error != null)
                Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: () => _load(reset: _retryReset),
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
          );
        },
      ),
    ),
  );
}
