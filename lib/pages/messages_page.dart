import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'private_messages_page.dart';
import 'reading_page.dart';
import 'user_page.dart';
import '../widgets/desktop_layout.dart';

/// 消息: private messages, and the replies, likes and mentions others sent.
class MessagesPage extends StatelessWidget {
  const MessagesPage({
    super.key,
    this.initialTab = 0,
    this.counts = const {},
    this.api,
  });

  /// Replaces the network client for the notification tabs, for tests.
  final TiebaApi? api;

  /// 0 私信, 1 回复我的, 2 收到的赞, 3 @我的.
  final int initialTab;

  /// Unread counts by tab index, shown as badges.
  final Map<int, int> counts;

  @override
  Widget build(BuildContext context) =>
      DesktopFrame(child: _buildPage(context));

  Widget _tab(String label, int index) {
    final count = counts[index] ?? 0;
    return Tab(
      child: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        offset: const Offset(18, -8),
        child: Text(label),
      ),
    );
  }

  Widget _buildPage(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        bottom: TabBar(
          tabs: [
            _tab('私信', 0),
            _tab('回复我的', 1),
            _tab('收到的赞', 2),
            _tab('@我的', 3),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          const PrivateMessagesPage(embedded: true),
          _MessagesList(kind: MessageKind.replies, api: api),
          _MessagesList(kind: MessageKind.likes, api: api),
          _MessagesList(kind: MessageKind.mentions, api: api),
        ],
      ),
    ),
  );
}

class _MessagesList extends StatefulWidget {
  const _MessagesList({required this.kind, this.api});
  final MessageKind kind;
  final TiebaApi? api;
  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList>
    with AutomaticKeepAliveClientMixin {
  late final _api = widget.api ?? TiebaApi();
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

  void _open(Json item) {
    final thread = {
      ...object(item['thread_info']),
      ...object(item['thread_content']),
    };
    final tid = firstText([item['thread_id'], thread['id']]);
    if (flag(item['is_del']) || tid.isEmpty || tid == '0') return;
    final floor = flag(item['is_floor']);
    final post = number(item['post_id']) > 0 ? '${item['post_id']}' : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadingPage(
          threadId: tid,
          title: firstText([item['title'], thread['title']], '查看帖子'),
          forum: firstText([item['fname'], thread['fname']]),
          targetPostId: floor ? null : post,
          targetReplyId: floor ? post : null,
          postId: floor && number(item['quote_pid']) > 0
              ? '${item['quote_pid']}'
              : null,
        ),
      ),
    );
  }

  /// The footer came into view: fetch the next page, no button needed.
  void _reachedEnd() {
    if (!_more || _busy || _error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
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
          final rows = widget.kind == MessageKind.likes
              ? groupLikes(visible)
              : [
                  for (final item in visible) [item],
                ];
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length + 1,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 68,
              endIndent: 16,
              color: Theme.of(context).colorScheme.outlineVariant
                  .withValues(alpha: .5),
            ),
            itemBuilder: (context, index) {
              if (index < rows.length) {
                return _NoticeRow(
                  kind: widget.kind,
                  items: rows[index],
                  user: _user,
                  onTap: () => _open(rows[index].first),
                );
              }
              _reachedEnd();
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _error != null
                      ? Column(
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: () => _load(reset: _retryReset),
                              child: const Text('重试'),
                            ),
                          ],
                        )
                      : _busy || _more
                      ? const CircularProgressIndicator()
                      : Text(
                          _items.isEmpty ? '暂无消息' : '没有更多了',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Likes on the same post become one row, newest first; the first item of
/// each group is the latest like.
List<List<Json>> groupLikes(List<Json> items) {
  final groups = <String, List<Json>>{};
  var unique = 0;
  for (final item in items) {
    final post = object(item['post_info']);
    final postId = firstText([item['post_id'], post['post_id'], post['id']]);
    final threadId = firstText([
      item['thread_id'],
      object(item['thread_info'])['id'],
    ]);
    final key = postId.isEmpty || postId == '0'
        ? (threadId.isEmpty ? 'item:${unique++}' : 'thread:$threadId')
        : 'post:$postId';
    (groups[key] ??= []).add(item);
  }
  return groups.values.toList();
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.kind,
    required this.items,
    required this.user,
    required this.onTap,
  });
  final MessageKind kind;
  final List<Json> items;
  final Json Function(Json item) user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final item = items.first;
    final thread = {
      ...object(item['thread_info']),
      ...object(item['thread_content']),
    };
    final title = firstText([
      item['title'],
      thread['title'],
    ], '查看帖子').replaceFirst(RegExp(r'^(?:(?:回复帖子|回复)\s*[:：]\s*)+'), '');
    final forum = firstText([item['fname'], thread['fname']]);
    final unavailable =
        flag(item['is_del']) ||
        firstText([item['thread_id'], thread['id']]).isEmpty;
    final likes = kind == MessageKind.likes;
    // What they wrote (replies, mentions), or what of mine they liked.
    final said = likes ? null : contentParts(item['content']);
    final mine = likes
        ? contentParts(object(item['post_info'])['content'])
        : contentParts(item['quote_content']);
    final people = <String, Json>{
      for (final i in items) userKey(user(i), i): user(i),
    }.values.toList();
    final names = people.take(2).map(author).join('、');
    final who = people.length > 2 ? '$names 等 ${people.length} 人' : names;
    final action = switch (kind) {
      MessageKind.replies => flag(item['is_floor']) ? '回复了你的评论' : '回复了你',
      MessageKind.likes => '赞了你',
      MessageKind.mentions => '提到了你',
    };
    final muted = text.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return InkWell(
      onTap: unavailable ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatars(people: people),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: who,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: '  $action',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        commentTime(item['time'] ?? item['op_time']),
                        style: muted,
                      ),
                    ],
                  ),
                  if (said != null && said.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    InlinePostContent(
                      parts: said,
                      maxLines: 4,
                      style: text.bodyLarge?.copyWith(height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mine.isNotEmpty)
                          InlinePostContent(
                            prefix: likes ? '' : '我：',
                            prefixColor: colors.primary,
                            parts: mine,
                            maxLines: 2,
                            style: text.bodySmall?.copyWith(
                              color: colors.onSurface,
                              height: 1.45,
                            ),
                          ),
                        if (mine.isNotEmpty) const SizedBox(height: 4),
                        Text(
                          [
                            if (unavailable) '原内容已不可用',
                            if (forum.isNotEmpty) '$forum吧',
                            title,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One avatar, or up to three overlapping ones for a group of likes.
class _Avatars extends StatelessWidget {
  const _Avatars({required this.people});
  final List<Json> people;

  @override
  Widget build(BuildContext context) {
    if (people.length <= 1) {
      return GestureDetector(
        onTap: people.isEmpty ? null : () => openUser(context, people.first),
        child: UserAvatar(user: people.isEmpty ? const {} : people.first),
      );
    }
    final shown = people.take(3).toList();
    final surface = Theme.of(context).colorScheme.surface;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 10.0,
              top: i * 10.0 / 2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                ),
                child: UserAvatar(user: shown[i], size: 24),
              ),
            ),
        ],
      ),
    );
  }
}
