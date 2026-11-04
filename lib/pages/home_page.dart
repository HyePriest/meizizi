import '../widgets/adaptive_feed.dart';
import '../widgets/app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../features/home/home_controller.dart';
import '../data/share_content.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/home_thread_card.dart';
import '../widgets/post_widgets.dart';
import '../widgets/shatter_effect.dart';
import '../widgets/bulk_sign_dialog.dart';
import 'reading_page.dart';
import 'search_page.dart';
import 'login_page.dart';
import 'profile_page.dart';
import 'hot_topics_page.dart';
import '../widgets/liquid_feed_switcher.dart';
import '../widgets/top_refresh_overlay.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _feed = HomeController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _shatterKeys = <String, GlobalKey>{};
  final _blocking = <String>{};
  var _scroll = ScrollController(keepScrollOffset: false);
  final _hotRefresh = ValueNotifier<int>(0);
  late final _searchCollapse = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 48,
    duration: const Duration(milliseconds: 240),
  );
  bool _switchingFeed = false;
  bool get _tapRefreshing => _feed.state.bottomRefresh;
  double _headerDestination = 0;
  final _feedHeaderOffsets = [0.0, 0.0];
  double _headerDragDistance = 0;
  int get _tab => _feed.tab;
  List<Json> get _items => _feed.state.items;
  Map<String, Json> get _users => _feed.state.users;
  bool get _busy => _feed.state.busy;
  bool get _hasMore => _feed.state.hasMore;
  String? get _error => _feed.state.error;
  bool _showHot = false, _hotVisited = false;
  int _accountEpoch = 0;
  final _scrollOffsets = <int, double>{};
  @override
  void initState() {
    super.initState();
    _feed.addListener(_feedChanged);
    LocalStore.instance.addListener(_localChanged);
    _scroll.addListener(_loadNearEnd);
    _load(reset: true);
  }

  void _feedChanged() {
    if (!mounted) return;
    if (_accountEpoch != _feed.accountEpoch) {
      _accountEpoch = _feed.accountEpoch;
      _scrollOffsets.clear();
      _replaceScroll(0);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadNearEnd();
    });
  }

  void _localChanged() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNearEnd();
      });
    }
  }

  void _loadNearEnd() {
    if (!(_tab == 0 && _showHot) &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_busy &&
        !_tapRefreshing &&
        _hasMore &&
        _error == null &&
        _tab != 2) {
      _load();
    }
  }

  @override
  void dispose() {
    _feed.removeListener(_feedChanged);
    LocalStore.instance.removeListener(_localChanged);
    _feed.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _hotRefresh.dispose();
    _searchCollapse.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) => _feed.load(reset: reset);

  Future<void> _refreshFromBottom() async {
    if (_tapRefreshing) return;
    final request = _feed.load(reset: true, fromBottom: true);
    final revision = _feed.revision;
    try {
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      if (mounted) _feed.reveal(revision);
      await request;
    } finally {
      if (mounted) _feed.reveal(revision);
    }
  }

  bool _trackRefreshGesture(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _feed.cancelBottomRefresh();
    }
    return false;
  }

  void _replaceScroll(double offset) {
    final previous = _scroll;
    previous.removeListener(_loadNearEnd);
    _scroll = ScrollController(
      initialScrollOffset: offset,
      keepScrollOffset: false,
    )..addListener(_loadNearEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  void _open(String name) {
    if (name.trim().isEmpty) return;
    _navigateFromHome(ReadingPage(forum: name));
  }

  Future<void> _navigateFromHome(Widget page) async {
    FocusScope.of(context).unfocus();
    _searchFocus.canRequestFocus = false;
    _feed.cancelBottomRefresh();
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) {
        _searchFocus.unfocus();
        _searchFocus.canRequestFocus = true;
      }
    }
  }

  void _openPost(Json item) => _navigateFromHome(
    ReadingPage(
      previewThread: {...item, 'author': _user(item)},
      threadId: '${item['id']}',
      title: '${item['title'] ?? ''}',
      forum: threadForumName(item).isEmpty ? null : threadForumName(item),
    ),
  );
  void _searchFor(String raw) {
    final word = raw.trim();
    if (word.isEmpty) return;
    _navigateFromHome(SearchPage(word: word));
  }

  Future<void> _bulkSign() async {
    FocusScope.of(context).unfocus();
    if (!AuthStore.instance.isLoggedIn) {
      final logged = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (logged != true || !mounted) return;
    }
    final task = BulkSignTask.instance;
    if (task.running) return;
    await task.start();
    if (mounted && task.finished) {
      ScaffoldMessenger.of(context)
          .showAppSnackBar(AppSnackBar(content: Text(task.summary)));
    }
  }

  Json _user(Json item) =>
      _users['${item['author_id']}'] ?? object(item['author']);
  Future<void> _block(String choice, Json item, Json user) async {
    final id = '${item['id']}';
    if (!_blocking.add(id)) return;
    try {
      await shatterRemove(_shatterKeys[id], () async {
        if (choice == 'forum') {
          await LocalStore.instance.blockForum(threadForumName(item));
        } else {
          await LocalStore.instance.blockUser(
            userKey(user, item),
            author(user),
          );
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('屏蔽保存失败，请重试')));
      }
    } finally {
      _blocking.remove(id);
    }
  }

  Future<void> _sharePost(Json item) async {
    try {
      await ShareContent.post(
        threadId: '${item['id']}',
        title: firstText([item['title']]),
        forum: threadForumName(item),
        post: {
          ...item,
          'author': {..._user(item), ...object(item['author'])},
        },
      ).share();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('无法打开分享，请稍后重试')));
      }
    }
  }

  Widget _entry(Json item) {
    if (_tab == 1) {
      final name = forumName(item);
      return Card(
        child: ListTile(
          leading: ForumAvatar(forum: item),
          title: Text('$name吧'),
          subtitle: ForumLevelBadge(
            user: {
              ...item,
              'level_id': item['level_id'] ?? item['level'],
              'is_like': 1,
            },
          ),
          trailing: SignButton(name: name, signed: flag(item['is_sign_in'])),
          onTap: () => _open(name),
        ),
      );
    }
    final user = _user(item), forum = threadForumName(item);
    return RepaintBoundary(
      key: _shatterKeys.putIfAbsent('${item['id']}', () => GlobalKey()),
      child: HomeThreadCard(
        thread: item,
        user: user,
        onOpenForum: () => _open(forum),
        onOpen: () => _openPost(item),
        onShare: () => _sharePost(item),
        onBlock: (choice) => _block(choice, item, user),
        onLikeChanged: _feed.updateLike,
      ),
    );
  }

  Widget _recentCard() {
    final store = LocalStore.instance;
    if (store.history.isEmpty && store.recent.isEmpty)
      return const SizedBox.shrink();
    final item = store.history.isEmpty ? null : store.history.first;
    final tid = item == null ? '' : firstText([item['id']]);
    final floor = tid.isEmpty ? 0 : number(store.readingPosition(tid)['floor']);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近浏览', style: Theme.of(context).textTheme.titleSmall),
            if (item != null && tid.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingPage(
                      threadId: tid,
                      title: firstText([item['title']]),
                      forum: firstText([item['forum']]),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              firstText([item['title']], '上次的帖子'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '继续阅读${floor > 1 ? ' · 第 $floor 楼' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ],
            if (store.recent.isNotEmpty) ...[
              if (tid.isNotEmpty) const Divider(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final name in store.recent)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text('$name吧'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _open(name),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final visible = _tab == 0
        ? _items
              .where((item) => !LocalStore.instance.hidden(item, _user(item)))
              .toList()
        : _items;
    return NotificationListener<ScrollNotification>(
      onNotification: _trackRefreshGesture,
      child: TopRefreshOverlay(
        refreshing: _tapRefreshing,
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: AdaptiveFeedView.builder(
            controller: _scroll,
            key: ValueKey(_tab),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            fullWidthFirst: true,
            fullWidthLast: true,
            itemCount: visible.length + 2,
            itemBuilder: (context, index) {
              if (index > 0 && index <= visible.length)
                return _entry(visible[index - 1]);
              if (index == 0)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tab == 1) ...[
                      _recentCard(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '我关注的吧',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          ListenableBuilder(
                            listenable: BulkSignTask.instance,
                            builder: (context, _) {
                              final task = BulkSignTask.instance;
                              return FilledButton.tonalIcon(
                                onPressed: task.running ? null : _bulkSign,
                                icon: Icon(
                                  task.allSigned
                                      ? Icons.check
                                      : Icons.event_available,
                                ),
                                label: Text(task.buttonLabel),
                              );
                            },
                          ),
                        ],
                      ),
                      ListenableBuilder(
                        listenable: BulkSignTask.instance,
                        builder: (context, _) {
                          final task = BulkSignTask.instance;
                          if (!task.finished) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => SafeArea(
                                  child: SizedBox(
                                    height:
                                        MediaQuery.sizeOf(context).height * .65,
                                    child: ListView(
                                      padding: const EdgeInsets.all(16),
                                      children: [
                                        Text(task.summary),
                                        const Divider(),
                                        for (final result in task.results)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Text(result),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              child: Text(
                                '已签 ${task.success} 个${task.unavailable > 0 ? ' · 跳过 ${task.unavailable} 个' : ''} · 查看结果',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      if (!AuthStore.instance.isLoggedIn)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Text('登录后查看已关注的吧并签到'),
                              TextButton(
                                onPressed: () => Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => const LoginPage(),
                                      ),
                                    ),
                                child: const Text('登录'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                );
              return Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: () =>
                                _load(reset: _feed.state.retryReset),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  if (_busy && !_tapRefreshing)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_hasMore && _error == null)
                    TextButton(onPressed: _load, child: const Text('加载下一页'))
                  else if (visible.isEmpty &&
                      _error == null &&
                      (_tab == 0 || AuthStore.instance.isLoggedIn))
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(_items.isNotEmpty ? '本页内容已被屏蔽' : '暂时没有内容'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _chooseFeed(bool hot) {
    if (_showHot == hot) return;
    _feed.cancelBottomRefresh();
    FocusScope.of(context).unfocus();
    _headerDragDistance = 0;
    // Keep the shared search header still while switching feeds.
    _feedHeaderOffsets[hot ? 1 : 0] = _searchCollapse.value;
    setState(() {
      _showHot = hot;
      if (hot) _hotVisited = true;
    });
  }

  bool _trackHeader(ScrollNotification notification) {
    if (_switchingFeed) return false;
    if (_tab == 0 &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification is ScrollUpdateNotification) {
      // Follow the user's direction, rather than requiring a return to the top.
      // Ignore ballistic/layout updates so the header cannot drive itself.
      if (notification.dragDetails == null) return false;
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_headerDragDistance.sign != delta.sign) _headerDragDistance = 0;
      _headerDragDistance += delta;
      if (_headerDragDistance.abs() >= 12 || notification.metrics.pixels <= 0) {
        final hidden = notification.metrics.pixels <= 0 || delta < 0
            ? 0.0
            : 48.0;
        _feedHeaderOffsets[_showHot ? 1 : 0] = hidden;
        if (_headerDestination != hidden) {
          _headerDestination = hidden;
          _searchCollapse.animateTo(hidden, curve: Curves.easeOutCubic);
        }
      }
    }
    return false;
  }

  Widget _searchBox() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
    child: SizedBox(
      height: 38,
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        onTapOutside: (_) => _searchFocus.unfocus(),
        textInputAction: TextInputAction.search,
        onSubmitted: _searchFor,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
  );

  void _switchBottom(int tab) {
    if (_tab == tab) {
      if (tab == 0 && !_switchingFeed) {
        _headerDestination = 0;
        _searchCollapse.animateTo(0, curve: Curves.easeOutCubic);
        _feedHeaderOffsets.fillRange(0, _feedHeaderOffsets.length, 0);
        _headerDragDistance = 0;
        if (_showHot) {
          _hotRefresh.value++;
        } else {
          _refreshFromBottom();
        }
      }
      return;
    }
    FocusScope.of(context).unfocus();
    if (_tab != 2) {
      _scrollOffsets[_tab] = _scroll.hasClients ? _scroll.offset : 0;
    }
    _replaceScroll(_scrollOffsets[tab] ?? 0);
    _feed.selectTab(tab);
    _searchCollapse.stop();
    if (tab == 0) {
      _headerDestination = _feedHeaderOffsets[_showHot ? 1 : 0];
      _searchCollapse.value = _headerDestination;
    }
  }

  Widget _navigationItem(
    int tab,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    final selected = _tab == tab;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        child: Tooltip(
          message: label,
          child: InkResponse(
            onTap: () => _switchBottom(tab),
            radius: 23,
            splashColor: colors.primary.withValues(alpha: .24),
            highlightColor: colors.primary.withValues(alpha: .10),
            child: SizedBox.expand(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: 22,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _tab == 2
        ? AppBar(
            toolbarHeight: 48,
            title: const Text('个人页'),
            actions: [
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('设置')),
                      body: const SettingsContent(),
                    ),
                  ),
                ),
              ),
            ],
          )
        : null,
    body: Row(
      children: [
        if (useTabletLandscape(context))
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _switchBottom,
                labelType: NavigationRailLabelType.all,
                minWidth: 88,
                groupAlignment: -1,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('首页'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.forum_outlined),
                    selectedIcon: Icon(Icons.forum),
                    label: Text('关注的吧'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: Text('个人页'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _tab == 2
              ? const ProfilePage()
              : SafeArea(
                  bottom: useTabletLandscape(context),
                  child: Column(
                    children: [
                      if (_tab != 0) _searchBox(),
                      Expanded(
                        child: _tab == 0
                            ? NotificationListener<ScrollNotification>(
                                onNotification: _trackHeader,
                                child: LiquidFeedSwitcher(
                                  header: AnimatedBuilder(
                                    animation: _searchCollapse,
                                    child: _searchBox(),
                                    builder: (_, child) => ClipRect(
                                      child: SizedBox(
                                        height: 48 - _searchCollapse.value,
                                        child: OverflowBox(
                                          alignment: Alignment.bottomCenter,
                                          minHeight: 48,
                                          maxHeight: 48,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onSwitching: (active) {
                                    _switchingFeed = active;
                                    _headerDragDistance = 0;
                                    if (active) {
                                      _feed.cancelBottomRefresh();
                                      _searchCollapse.stop();
                                      _headerDestination =
                                          _searchCollapse.value;
                                    }
                                  },
                                  selected: _showHot ? 1 : 0,
                                  onSelected: (index) =>
                                      _chooseFeed(index == 1),
                                  onPrepare: (index) {
                                    if (index == 1 && !_hotVisited) {
                                      setState(() => _hotVisited = true);
                                    }
                                  },
                                  children: [
                                    _content(),
                                    if (_hotVisited)
                                      HotTopicsView(refreshSignal: _hotRefresh)
                                    else
                                      const SizedBox.shrink(),
                                  ],
                                ),
                              )
                            : _content(),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
    bottomNavigationBar: useTabletLandscape(context)
        ? null
        : Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    _navigationItem(0, Icons.home_outlined, Icons.home, '首页'),
                    _navigationItem(
                      1,
                      Icons.forum_outlined,
                      Icons.forum,
                      '关注的吧',
                    ),
                    _navigationItem(
                      2,
                      Icons.person_outline,
                      Icons.person,
                      '个人页',
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
