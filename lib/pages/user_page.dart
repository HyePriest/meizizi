import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tieba_api.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/post_widgets.dart';
import '../widgets/reliable_image.dart';
import '../widgets/thread_thumbnails.dart';
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

/// One list of a user's posts: their threads or their replies.
class _Feed {
  final items = <Json>[];
  bool busy = false, more = true, retryReset = true;
  int page = 0;
  String? error;
}

class _UserPageState extends State<UserPage> {
  late final _api = widget.api ?? TiebaApi();
  Json _user = {};
  bool _profileLoaded = false;
  String? _profileError;
  int _tab = 0;
  final _feeds = [_Feed(), _Feed()];
  _Feed get _feed => _feeds[_tab];
  bool get _replies => _tab == 1;

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
    _api.close();
    super.dispose();
  }

  Future<void> _refresh() async {
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
      if (_uid.isEmpty || _uid == '0') return;
    }
    for (final feed in _feeds) {
      feed
        ..items.clear()
        ..page = 0
        ..more = true
        ..error = null;
    }
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final feed = _feed;
    final replies = _replies;
    if (feed.busy) return;
    feed
      ..retryReset = reset
      ..busy = true
      ..error = null;
    setState(() {});
    try {
      if (_uid.isEmpty || _uid == '0') {
        throw const TiebaException('暂时无法获取该用户的主页');
      }
      final page = reset ? 1 : feed.page + 1;
      final result = await _api.userPosts(_uid, page, replies: replies);
      if (!mounted) return;
      final incoming = objects(result.data['post_list']);
      String key(Json p) => replies
          ? firstText([p['post_id'], p['id']])
          : firstText([p['thread_id'], p['tid'], p['id']]);
      if (reset) feed.items.clear();
      final seen = feed.items.map(key).toSet();
      feed.items.addAll(incoming.where((p) => seen.add(key(p))));
      feed
        ..page = page
        ..more = result.data.containsKey('has_more')
            ? flag(result.data['has_more'])
            : incoming.length >= 20;
    } catch (e) {
      feed.error = e is TiebaException ? e.message : '加载失败，请重试';
    } finally {
      feed.busy = false;
      if (mounted) setState(() {});
    }
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (_feed.page == 0 && !_feed.busy) _load(reset: true);
  }

  void _openPost(Json post) {
    final tid = firstText([post['thread_id'], post['tid'], post['id']]);
    if (tid.isEmpty) return;
    final reply = _replies && number(post['post_id']) > 0;
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

  @override
  Widget build(BuildContext context) => DesktopFrame(
    child: DesktopRefreshShortcut(onRefresh: _refresh, child: _page(context)),
  );

  Widget _page(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _UserBanner(user: _user),
            SliverToBoxAdapter(
              child: _UserHeader(
                user: _user,
                loaded: _profileLoaded,
                error: _profileError,
                onRetry: _refresh,
                onConnections: _openConnections,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsHeader(
                selected: _tab,
                threads: number(_user['thread_num']),
                replies: number(_user['post_num']),
                onSelected: _selectTab,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              sliver: SliverList.builder(
                itemCount: feed.items.length,
                itemBuilder: (context, index) {
                  final post = feed.items[index];
                  return _replies
                      ? _ReplyCard(post: post, onTap: () => _openPost(post))
                      : _ThreadCard(post: post, onTap: () => _openPost(post));
                },
              ),
            ),
            SliverToBoxAdapter(child: _feedFooter(feed)),
          ],
        ),
      ),
    );
  }

  Widget _feedFooter(_Feed feed) {
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: feed.error != null
            ? Column(
                children: [
                  Text(feed.error!, style: muted, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _load(reset: feed.retryReset),
                    child: const Text('重试'),
                  ),
                ],
              )
            : feed.busy
            ? const CircularProgressIndicator()
            : feed.more
            ? TextButton(onPressed: _load, child: const Text('加载更多'))
            : Text(
                feed.items.isEmpty
                    ? (_replies ? '没有可公开查看的回复' : '没有可公开查看的主题帖')
                    : '没有更多了',
                style: muted,
              ),
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

/// The cover image across the top; the page title appears once it scrolls away.
class _UserBanner extends StatelessWidget {
  const _UserBanner({required this.user});
  final Json user;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cover = httpsImage(user['bg_pic']);
    final top = MediaQuery.paddingOf(context).top;
    const expanded = 150.0;
    return SliverAppBar(
      pinned: true,
      expandedHeight: expanded,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapse =
              ((expanded + top - constraints.maxHeight) /
                      (expanded - kToolbarHeight))
                  .clamp(0.0, 1.0);
          final fallback = DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary.withValues(alpha: .55),
                  colors.primaryContainer,
                ],
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 1 - collapse,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cover.isEmpty
                        ? fallback
                        : ReliableImage(
                            urls: [cover],
                            fit: BoxFit.cover,
                            fallback: fallback,
                          ),
                    // Keeps the back button and status bar readable on any cover.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x00000000)],
                          stops: [0, .6],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 56,
                right: 16,
                top: top,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: collapse,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      author(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: '返回',
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: .18),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
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
          // The avatar rises into the cover; only its lower part takes space.
          SizedBox(
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: UserAvatar(user: user, size: 80),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
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
                        sex == 1 ? Icons.male_rounded : Icons.female_rounded,
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
                      await Clipboard.setData(ClipboardData(text: tiebaId));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showAppSnackBar(
                        const AppSnackBar(content: Text('贴吧 ID 已复制')),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '贴吧 ID：$tiebaId',
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
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
