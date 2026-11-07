import 'adaptive_feed.dart';

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../features/reading/reading_controller.dart';
import 'forum_category_bar.dart';
import 'directional_page_drag.dart';
import 'forum_thread_card.dart';
import 'page_drag.dart';

/// One vertical header shared by native, independently retained feed pages.
class ForumFeedPager extends StatefulWidget {
  const ForumFeedPager({
    super.key,
    required this.api,
    required this.primaryReader,
    required this.loadPrimary,
    required this.outerController,
    required this.header,
    required this.categoryBar,
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.levelNames,
    required this.decorateUser,
    this.refreshSignal,
  });

  final TiebaApi api;
  final ReadingController primaryReader;

  /// Each change reloads the visible category (desktop refresh button, F5).
  final Listenable? refreshSignal;
  final Future<void> Function(bool reset) loadPrimary;
  final ScrollController outerController;
  final Widget header, categoryBar;
  final List<ReadingQuery> categories;
  final int selected;
  final ValueChanged<int> onSelected;
  final Map<int, String> levelNames;
  final Json Function(Json user) decorateUser;

  @override
  State<ForumFeedPager> createState() => _ForumFeedPagerState();
}

class _ForumFeedPagerState extends State<ForumFeedPager> {
  late final _pages = PageController(initialPage: widget.selected);
  // Header and feed share one drag; only one finger gesture drives the pages.
  late final _pageDrag = PageDrag(_pages);

  @override
  void didUpdateWidget(covariant ForumFeedPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected &&
        _pages.hasClients &&
        _pages.page!.round() != widget.selected) {
      // Selection from a chip. Page gestures report selection as they cross the midpoint.
      _pages.animateToPage(
        widget.selected,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageDrag.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NestedScrollView(
    controller: widget.outerController,
    physics: const AlwaysScrollableScrollPhysics(),
    headerSliverBuilder: (context, scrolled) => [
      SliverToBoxAdapter(
        child: DirectionalPageDragArea(drag: _pageDrag, child: widget.header),
      ),
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: ForumCategoryHeader(child: widget.categoryBar),
        ),
      ),
    ],
    // PageView's own drag would accept slanted vertical scrolls, so page
    // swipes come from the directional recognizer instead.
    body: DirectionalPageDragArea(
      drag: _pageDrag,
      child: PageView.builder(
        controller: _pages,
        physics: const PageScrollPhysics(
          parent: NeverScrollableScrollPhysics(),
        ),
        onPageChanged: widget.onSelected,
        itemCount: widget.categories.length,
        itemBuilder: (context, index) {
          final query = widget.categories[index];
          final primary = query.section == null && query.category == '热门';
          return _ForumFeed(
            key: ValueKey(
              '${AuthStore.instance.activeId}:${query.section?.id ?? query.category}',
            ),
            api: widget.api,
            query: query,
            seed: widget.primaryReader.data,
            primaryReader: primary ? widget.primaryReader : null,
            loadPrimary: widget.loadPrimary,
            active: index == widget.selected,
            levelNames: widget.levelNames,
            decorateUser: widget.decorateUser,
            refreshSignal: widget.refreshSignal,
          );
        },
      ),
    ),
  );
}

class _ForumFeed extends StatefulWidget {
  const _ForumFeed({
    super.key,
    required this.api,
    required this.query,
    required this.seed,
    required this.active,
    required this.primaryReader,
    required this.loadPrimary,
    required this.levelNames,
    required this.decorateUser,
    this.refreshSignal,
  });
  final TiebaApi api;
  final ReadingQuery query;
  final ReadingData seed;
  final bool active;
  final ReadingController? primaryReader;
  final Future<void> Function(bool reset) loadPrimary;
  final Map<int, String> levelNames;
  final Json Function(Json user) decorateUser;
  final Listenable? refreshSignal;

  @override
  State<_ForumFeed> createState() => _ForumFeedState();
}

class _ForumFeedState extends State<_ForumFeed>
    with AutomaticKeepAliveClientMixin {
  late final ReadingController _reader;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reader =
        widget.primaryReader ??
        ReadingController(
          widget.api,
          initialData: ReadingData(
            forum: widget.seed.forum,
            result: widget.seed.result,
            users: widget.seed.users,
          ),
        );
    _reader.addListener(_changed);
    widget.refreshSignal?.addListener(_refreshRequested);
    if (widget.primaryReader == null) _load(true);
  }

  /// Same as pulling down to refresh.
  Future<void> _refresh() async {
    if (widget.primaryReader == null) await widget.loadPrimary(true);
    if (mounted) await _load(true);
  }

  void _refreshRequested() {
    if (widget.active) _refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load(bool reset) async {
    if (_reader.busy) return;
    if (reset) _emptyLoads = 0;
    if (widget.primaryReader != null) {
      await widget.loadPrimary(reset);
    } else {
      await _reader.load(widget.query, reset: reset);
    }
  }

  /// Start loading the next page this far before the end of the list.
  static const _prefetchExtent = 600.0;

  /// Pages in a row that added no visible thread (forum pages can overlap).
  /// After this many, automatic loading pauses so it cannot loop forever.
  static const _maxEmptyLoads = 3;
  int _emptyLoads = 0;
  ScrollMetrics? _metrics;

  bool get _canLoadMore =>
      widget.active &&
      _reader.data.hasMore &&
      !_reader.busy &&
      _reader.error == null &&
      _emptyLoads < _maxEmptyLoads;

  void _maybeLoadMore() {
    final metrics = _metrics;
    if (metrics == null || metrics.extentAfter >= _prefetchExtent) return;
    if (_canLoadMore) _loadMore();
  }

  /// Threads shown after hiding blocked authors.
  List<Json> _visibleRows() {
    final data = _reader.data;
    return data.items
        .where(
          (item) => !LocalStore.instance.userBlocked({
            ...?data.users['${item['author_id']}'],
            ...object(item['author']),
          }, item),
        )
        .toList();
  }

  Future<void> _loadMore() async {
    final before = _visibleRows().length;
    await _load(false);
    if (!mounted || _reader.error != null) return;
    // Rows from blocked authors are hidden, so only visible rows count.
    final grew = _visibleRows().length > before;
    setState(() => _emptyLoads = grew ? 0 : _emptyLoads + 1);
    // New rows change the list size and report fresh metrics on their own.
    // Without new rows nothing moves, so check again with the same position.
    if (!grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    }
  }

  bool _onScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(depth: 0, :final metrics) => metrics,
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _metrics = metrics;
      _maybeLoadMore();
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant _ForumFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_refreshRequested);
      widget.refreshSignal?.addListener(_refreshRequested);
    }
    // A tab that was swiped to may already be scrolled near its end.
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    }
  }

  @override
  void dispose() {
    _reader.removeListener(_changed);
    widget.refreshSignal?.removeListener(_refreshRequested);
    if (widget.primaryReader == null) _reader.dispose();
    super.dispose();
  }

  Widget _footer() {
    if (_reader.busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_reader.error != null) {
      return Column(
        children: [
          Text(_reader.error!, textAlign: TextAlign.center),
          TextButton(
            onPressed: () => _load(_reader.data.page == 0),
            child: const Text('重试'),
          ),
        ],
      );
    }
    final warning = firstText([
      _reader.data.result?.data['forum_parse_warning'],
    ]);
    return Column(
      children: [
        if (warning.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(warning)),
        if (_reader.data.hasMore && _emptyLoads >= _maxEmptyLoads)
          TextButton(
            onPressed: () {
              setState(() => _emptyLoads = 0);
              _loadMore();
            },
            child: const Text('暂时没有加载到新帖子，点击重试'),
          )
        else if (_reader.data.hasMore)
          // Loading starts automatically before this footer scrolls into view.
          const Padding(
            padding: EdgeInsets.all(24),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _reader.data.items.isEmpty && warning.isEmpty
                  ? '当前分类暂无帖子'
                  : '已经到底了',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _reader.data;
    final rows = _visibleRows();
    final indices = {
      for (var i = 0; i < rows.length; i++) '${rows[i]['id']}': i,
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<Notification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            key: PageStorageKey(
              '${AuthStore.instance.activeId}:${widget.query.section?.id ?? widget.query.category}',
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: AdaptiveFeedSliver(
                  itemCount: rows.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? indices[key.value] : null,
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    return ForumThreadCard(
                      key: ValueKey('${item['id']}'),
                      thread: item,
                      user: widget.decorateUser({
                        ...?data.users['${item['author_id']}'],
                        ...object(item['author']),
                      }),
                      forum: widget.query.forum!,
                      latestReply:
                          widget.query.section == null &&
                          widget.query.category == '最新回复',
                      levelNames: widget.levelNames,
                      onLikeChanged: (source, patch) =>
                          _reader.updateLike(source, patch, firstFloor: false),
                    );
                  },
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(alignment: Alignment.topCenter, child: _footer()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
