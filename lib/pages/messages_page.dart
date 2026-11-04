import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'reading_page.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        bottom: const TabBar(
          tabs: [
            Tab(text: '回复我的'),
            Tab(text: '收到的赞'),
            Tab(text: '@我的'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _MessagesList(kind: MessageKind.replies),
          _MessagesList(kind: MessageKind.likes),
          _MessagesList(kind: MessageKind.mentions),
        ],
      ),
    ),
  );
}

class _MessagesList extends StatefulWidget {
  const _MessagesList({required this.kind});
  final MessageKind kind;
  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList>
    with AutomaticKeepAliveClientMixin {
  final _api = TiebaApi();
  final _items = <Json>[];
  late final String _account = AuthStore.instance.activeId;
  int _page = 0;
  String _cursor = '';
  String? _error;
  bool _busy = false, _more = true, _retryReset = true;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (_account == AuthStore.instance.activeId || !mounted) return;
    setState(() {
      _items.clear();
      _more = false;
      _error = '账号已切换，请重新打开通知';
    });
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    _api.close();
    super.dispose();
  }

  String _key(Json item) =>
      '${item['id']}:${item['post_id']}:${item['time'] ?? item['op_time']}:${item['op_user_id'] ?? object(item['replyer'])['id']}';
  Future<void> _load({bool reset = false}) async {
    if (_busy || _account != AuthStore.instance.activeId) return;
    _retryReset = reset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = await _api.messages(
        widget.kind,
        page,
        cursor: reset ? '' : _cursor,
      );
      if (!mounted || _account != AuthStore.instance.activeId) return;
      setState(() {
        if (reset) _items.clear();
        final seen = _items.map(_key).toSet();
        _items.addAll(result.items.where((item) => seen.add(_key(item))));
        _page = page;
        _cursor = result.cursor;
        _more = result.hasMore;
      });
    } catch (e) {
      if (mounted && _account == AuthStore.instance.activeId) {
        setState(() => _error = e is TiebaException ? e.message : '消息加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Json _user(Json item) =>
      object(item[widget.kind == MessageKind.likes ? 'agreeer' : 'replyer']);
  Widget _card(Json item) {
    final user = _user(item);
    final thread = {
      ...object(item['thread_info']),
      ...object(item['thread_content']),
    };
    final title = firstText([item['title'], thread['title']], '查看帖子');
    final forum = firstText([item['fname'], thread['fname']]);
    final content = widget.kind == MessageKind.likes
        ? object(item['post_info'])['content']
        : item['content'];
    final quote = item['quote_content'];
    final tid = firstText([item['thread_id'], thread['id']]);
    final unavailable = flag(item['is_del']) || tid.isEmpty || tid == '0';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: unavailable
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadingPage(
                    threadId: tid,
                    title: title,
                    forum: forum,
                    targetPostId:
                        !flag(item['is_floor']) && number(item['post_id']) > 0
                        ? '${item['post_id']}'
                        : null,
                    targetReplyId:
                        flag(item['is_floor']) && number(item['post_id']) > 0
                        ? '${item['post_id']}'
                        : null,
                    postId:
                        flag(item['is_floor']) && number(item['quote_pid']) > 0
                        ? '${item['quote_pid']}'
                        : null,
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserHeader(
                user: user,
                subtitle:
                    '${switch (widget.kind) {
                      MessageKind.replies => '回复了你',
                      MessageKind.likes => '赞了你的内容',
                      MessageKind.mentions => '提到了你',
                    }} · ${commentTime(item['time'] ?? item['op_time'])}',
              ),
              if (contentParts(content).isNotEmpty) ...[
                const SizedBox(height: 10),
                InlinePostContent(parts: contentParts(content), maxLines: 8),
              ],
              if (contentParts(quote).isNotEmpty) ...[
                const SizedBox(height: 8),
                InlinePostContent(
                  prefix: '我的原评论：',
                  parts: contentParts(quote),
                  maxLines: 4,
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${unavailable ? '原内容已不可用 · ' : ''}$title${forum.isEmpty ? '' : '\n$forum吧'}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListenableBuilder(
        listenable: LocalStore.instance,
        builder: (context, _) {
          final visible = _items
              .where((item) => !LocalStore.instance.userBlocked(_user(item)))
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: visible.length + 1,
            itemBuilder: (context, index) {
              if (index < visible.length) return _card(visible[index]);
              return Column(
                children: [
                  if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => _load(reset: _retryReset),
                      child: const Text('重试'),
                    ),
                  ],
                  if (_busy)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_more && _error == null)
                    TextButton(onPressed: _load, child: const Text('加载更多'))
                  else if (_items.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('暂无通知')),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
