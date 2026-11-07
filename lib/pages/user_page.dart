import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tieba_api.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/post_widgets.dart';
import '../widgets/thread_thumbnails.dart';
import '../widgets/directional_page_drag.dart';
import '../widgets/page_drag.dart';
import 'reading_page.dart';
import 'user_connections_page.dart';
import '../widgets/desktop_layout.dart';

void openUser(BuildContext context, Json user) {
  if (firstText([user['id'], user['user_id'], user['portrait']]).isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => UserPage(user: user)));
}

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.user, this.api});
  final Json user;

  /// Replaces the network client, for tests and previews.
  final TiebaApi? api;
  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late final _api = widget.api ?? TiebaApi();
  late final _pages = PageController();
  late final _pageDrag = PageDrag(_pages);
  // Pull to refresh reloads both lists.
  final _refreshSignal = ValueNotifier(0);
  // The app bar shows the name once the header's name has scrolled away.
  final _titleVisible = ValueNotifier(false);
  Json _user = {};
  bool _profileLoaded = false;
  String? _profileError;
  int _tab = 0;

  String get _uid => firstText([_user['id'], _user['user_id']]);

  void _openConnections(UserConnections kind) {
    if (_uid.isEmpty || _uid == '0') return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserConnectionsPage(uid: _uid, kind: kind),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _refresh();
  }

  @override
  void dispose() {
    _pageDrag.cancel();
    _pages.dispose();
    _refreshSignal.dispose();
    _titleVisible.dispose();
    _api.close();
    super.dispose();
  }

  // The lists start their first page themselves once the profile is in.
  bool _firstLoad = true;

  Future<void> _refresh() async {
    final reloadLists = !_firstLoad;
    _firstLoad = false;
    setState(() => _profileError = null);
    try {
      final result = await _api.userProfile(widget.user);
      if (!mounted) return;
      setState(() {
        _user = {...widget.user, ...object(result.data['user'])};
        _profileLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _profileError = e is TiebaException ? e.message : '主页加载失败，请重试',
      );
    }
    if (reloadLists) _refreshSignal.value++;
  }

  void _selectTab(int tab) {
    if (tab == _tab || !_pages.hasClients) return;
    _pages.animateToPage(
      tab,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  bool _trackTitle(ScrollNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _titleVisible.value = notification.metrics.pixels > 72;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => DesktopFrame(
    child: DesktopRefreshShortcut(onRefresh: _refresh, child: _page(context)),
  );

  Widget _page(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: _refresh,
      edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
      // Pull from either the header or the top of a list.
      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
      child: NotificationListener<ScrollNotification>(
        onNotification: _trackTitle,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              surfaceTintColor: Colors.transparent,
              title: ValueListenableBuilder<bool>(
                valueListenable: _titleVisible,
                builder: (_, visible, _) => AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(author(_user)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: DirectionalPageDragArea(
                drag: _pageDrag,
                child: _UserHeader(
                  user: _user,
                  loaded: _profileLoaded,
                  error: _profileError,
                  onRetry: _refresh,
                  onConnections: _openConnections,
                ),
              ),
            ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  selected: _tab,
                  threads: number(_user['thread_num']),
                  replies: number(_user['post_num']),
                  onSelected: _selectTab,
                ),
              ),
            ),
          ],
          // PageView's own drag would take slanted vertical scrolls, so only
          // mostly-sideways swipes switch between 主题帖 and 回复.
          body: DirectionalPageDragArea(
            drag: _pageDrag,
            child: PageView(
              controller: _pages,
              physics: const PageScrollPhysics(
                parent: NeverScrollableScrollPhysics(),
              ),
              onPageChanged: (tab) => setState(() => _tab = tab),
              children: [
                for (final replies in [false, true])
                  _UserPosts(
                    key: ValueKey('$_uid:$replies'),
                    api: _api,
                    uid: _uid,
                    replies: replies,
                    waiting: !_profileLoaded && _profileError == null,
                    refreshSignal: _refreshSignal,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One of the user's lists: their threads or their replies. Pages load on
/// their own as the end comes into view.
class _UserPosts extends StatefulWidget {
  const _UserPosts({
    super.key,
    required this.api,
    required this.uid,
    required this.replies,
    required this.waiting,
    required this.refreshSignal,
  });
  final TiebaApi api;
  final String uid;
  final bool replies;

  /// The profile, which gives the user ID, is still loading.
  final bool waiting;
  final Listenable refreshSignal;

  @override
  State<_UserPosts> createState() => _UserPostsState();
}

class _UserPostsState extends State<_UserPosts>
    with AutomaticKeepAliveClientMixin {
  final _items = <Json>[];
  bool _busy = false, _more = true, _retryReset = true;
  int _page = 0, _emptyLoads = 0, _revision = 0;
  String? _error;

  /// Pages in a row that added nothing new. The server sends no has_more and
  /// often returns short pages, so stop only after a few empty ones.
  static const _maxEmptyLoads = 2;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_reset);
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_reset);
    super.dispose();
  }

  void _reset() => _load(reset: true);

  String _key(Json p) => widget.replies
      ? firstText([p['post_id'], p['id']])
      : firstText([p['thread_id'], p['tid'], p['id']]);

  Future<void> _load({bool reset = false}) async {
    if (_busy && !reset) return;
    final revision = ++_revision;
    _retryReset = reset;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) _emptyLoads = 0;
    });
    try {
      final uid = widget.uid;
      if (uid.isEmpty || uid == '0') {
        throw const TiebaException('暂时无法获取该用户的主页');
      }
      final page = reset ? 1 : _page + 1;
      final result = await widget.api.userPosts(
        uid,
        page,
        replies: widget.replies,
      );
      if (!mounted || revision != _revision) return;
      final incoming = objects(result.data['post_list']);
      setState(() {
        if (reset) _items.clear();
        final seen = _items.map(_key).toSet();
        final before = _items.length;
        _items.addAll(incoming.where((p) => seen.add(_key(p))));
        _page = page;
        _emptyLoads = _items.length > before ? 0 : _emptyLoads + 1;
        _more = result.data.containsKey('has_more')
            ? flag(result.data['has_more'])
            : incoming.isNotEmpty && _emptyLoads < _maxEmptyLoads;
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _error = e is TiebaException ? e.message : '加载失败，请重试');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  void _open(Json post) {
    final tid = firstText([post['thread_id'], post['tid'], post['id']]);
    if (tid.isEmpty) return;
    final reply = widget.replies && number(post['post_id']) > 0;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadingPage(
          threadId: tid,
          title: _threadTitle(post),
          forum: threadForumName(post),
          targetPostId: reply ? '${post['post_id']}' : null,
        ),
      ),
    );
  }

  /// The end of the list came into view: fetch the next page.
  void _reachedEnd() {
    if (widget.waiting || !_more || _busy || _error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_busy) _load(reset: _page == 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey('posts-${widget.replies}'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverList.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final post = _items[index];
                return widget.replies
                    ? _ReplyCard(post: post, onTap: () => _open(post))
                    : _ThreadCard(post: post, onTap: () => _open(post));
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                _reachedEnd();
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: _error != null
                        ? Column(
                            children: [
                              Text(
                                _error!,
                                style: muted,
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: () => _load(reset: _retryReset),
                                child: const Text('重试'),
                              ),
                            ],
                          )
                        : _busy || _more || widget.waiting
                        ? const CircularProgressIndicator()
                        : Text(
                            _items.isEmpty
                                ? (widget.replies
                                      ? '没有可公开查看的回复'
                                      : '没有可公开查看的主题帖')
                                : '没有更多了',
                            style: muted,
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _threadTitle(Json post) {
  final title = plainText(firstText([post['title']]))
      .trim()
      .replaceFirst(RegExp(r'^(?:(?:回复帖子|回复)\s*[:：]\s*)+'), '');
  return title.isEmpty ? '查看帖子' : title;
}

String _count(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({
    required this.user,
    required this.loaded,
    required this.error,
    required this.onRetry,
    required this.onConnections,
  });
  final Json user;
  final bool loaded;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<UserConnections> onConnections;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final level = number(object(user['user_growth'])['level_id']);
    final age = firstText([user['tb_age']]);
    final ip = firstText([user['ip_address']]);
    final member = firstText([
      object(user['pay_member_info'])['expire_remind'],
    ]);
    final tiebaId = firstText([user['tieba_uid']]);
    final intro = firstText([user['intro']]).trim();
    final sex = number(user['sex']);
    final forums = objects(user['likeForum'])
        .where((f) => firstText([f['forum_name']]).isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(user: user, size: 72),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  author(user),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (sex == 1 || sex == 2) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  sex == 1
                                      ? Icons.male_rounded
                                      : Icons.female_rounded,
                                  size: 20,
                                  color: sex == 1
                                      ? const Color(0xff4a8af4)
                                      : const Color(0xffef6c9c),
                                ),
                              ],
                            ],
                          ),
                          if (tiebaId.isNotEmpty)
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: tiebaId),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showAppSnackBar(
                                  const AppSnackBar(content: Text('贴吧 ID 已复制')),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  '贴吧 ID：$tiebaId',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (level > 0) _Tag('Lv.$level', color: colors.primary),
                    if (age.isNotEmpty) _Tag('吧龄 $age 年'),
                    if (ip.isNotEmpty) _Tag('IP 属地 $ip'),
                    if (member.isNotEmpty)
                      _Tag(member, color: const Color(0xffd88a1c)),
                  ],
                ),
                if (intro.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(intro, style: text.bodyMedium?.copyWith(height: 1.5)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Stat(
                      label: '关注',
                      value: number(user['concern_num']),
                      onTap: () => onConnections(UserConnections.follows),
                    ),
                    _Stat(
                      label: '粉丝',
                      value: number(user['fans_num']),
                      onTap: () => onConnections(UserConnections.fans),
                    ),
                    _Stat(
                      label: '获赞',
                      value: number(
                        user['total_agree_num'] ??
                            object(user['user_agree_info'])['total_agree_num'],
                      ),
                    ),
                    _Stat(
                      label: '关注的吧',
                      value: number(user['my_like_num']),
                      onTap: () => onConnections(UserConnections.forums),
                    ),
                  ],
                ),
                if (forums.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '常逛的吧',
                    style: text.titleSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final forum in forums.take(8))
                        ActionChip(
                          label: Text('${forum['forum_name']}吧'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ReadingPage(forum: '${forum['forum_name']}'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (error != null && !loaded) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                      TextButton(onPressed: onRetry, child: const Text('重试')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: tone, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                _count(value),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({
    required this.selected,
    required this.threads,
    required this.replies,
    required this.onSelected,
  });
  final int selected, threads, replies;
  final ValueChanged<int> onSelected;

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final colors = Theme.of(context).colorScheme;
    Widget tab(int index, String label, int count) {
      final active = index == selected;
      return Expanded(
        child: InkWell(
          onTap: () => onSelected(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                count > 0 ? '$label ${_count(count)}' : label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: active ? colors.onSurface : colors.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 24 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: overlaps
                  ? colors.outlineVariant.withValues(alpha: .6)
                  : Colors.transparent,
              width: .5,
            ),
          ),
        ),
        child: Row(children: [tab(0, '主题帖', threads), tab(1, '回复', replies)]),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) =>
      old.selected != selected ||
      old.threads != threads ||
      old.replies != replies;
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.onTap, required this.children});
  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}

Widget _postMeta(BuildContext context, Json post) {
  final colors = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.labelSmall
      ?.copyWith(color: colors.onSurfaceVariant);
  final forum = threadForumName(post);
  final time = post['create_time'] ?? post['time'];
  return Row(
    children: [
      if (forum.isNotEmpty)
        Flexible(
          child: Text(
            '$forum吧',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (number(time) > 0) ...[
        if (forum.isNotEmpty) Text('  ·  ', style: style),
        Text(commentTime(time), style: style),
      ],
    ],
  );
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.post, required this.onTap});
  final Json post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = objects(post['abstract'])
        .map((p) => '${p['text'] ?? ''}')
        .join()
        .trim();
    return _PostCard(
      onTap: onTap,
      children: [
        _postMeta(context, post),
        const SizedBox(height: 8),
        Text(
          firstText([post['title']], '查看帖子'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        ThreadThumbnails(thread: post),
        const SizedBox(height: 10),
        _counts(context, post),
      ],
    );
  }
}

Widget _counts(BuildContext context, Json post) {
  final colors = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.labelSmall
      ?.copyWith(color: colors.onSurfaceVariant);
  final replies = number(post['reply_num']);
  final agrees = number(
    object(post['agree'])['agree_num'] ?? post['agree_num'],
  );
  return Row(
    children: [
      Icon(
        Icons.mode_comment_outlined,
        size: 14,
        color: colors.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Text(_count(replies), style: style),
      const SizedBox(width: 16),
      Icon(Icons.thumb_up_outlined, size: 14, color: colors.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(_count(agrees), style: style),
    ],
  );
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.post, required this.onTap});
  final Json post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parts = contentParts(post['content']);
    return _PostCard(
      onTap: onTap,
      children: [
        _postMeta(context, post),
        const SizedBox(height: 8),
        if (parts.isNotEmpty)
          InlinePostContent(
            parts: parts,
            maxLines: 4,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.5),
          )
        else
          Text(
            flag(post['is_post_deleted']) ? '这条回复已删除' : '这条回复的正文暂不可用',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '原帖  ',
                  style: TextStyle(color: colors.primary),
                ),
                TextSpan(text: _threadTitle(post)),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
