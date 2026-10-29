import 'adaptive_feed.dart';

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../features/reading/reading_controller.dart';
import 'forum_category_bar.dart';
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
  });

  final TiebaApi api;
  final ReadingController primaryReader;
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
  late final _headerDrag = PageDrag(_pages);

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
    _headerDrag.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NestedScrollView(
    controller: widget.outerController,
    physics: const AlwaysScrollableScrollPhysics(),
    headerSliverBuilder: (context, scrolled) => [
      SliverToBoxAdapter(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) =>
              _headerDrag.update(details.delta, details.globalPosition),
          onHorizontalDragEnd: (details) => _headerDrag.end(details.velocity),
          onHorizontalDragCancel: _headerDrag.cancel,
          child: widget.header,
        ),
      ),
      SliverOverlapAbsorber(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: ForumCategoryHeader(child: widget.categoryBar),
        ),
      ),
    ],
    body: PageView.builder(
      controller: _pages,
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
        );
      },
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
  });
  final TiebaApi api;
  final ReadingQuery query;
  final ReadingData seed;
  final bool active;
  final ReadingController? primaryReader;
  final Future<void> Function(bool reset) loadPrimary;
  final Map<int, String> levelNames;
  final Json Function(Json user) decorateUser;

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
    if (widget.primaryReader == null) _load(true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load(bool reset) async {
    if (_reader.busy) return;
    if (widget.primaryReader != null) {
      await widget.loadPrimary(reset);
    } else {
      await _reader.load(widget.query, reset: reset);
    }
  }

  @override
  void dispose() {
    _reader.removeListener(_changed);
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
        if (_reader.data.hasMore)
          TextButton(onPressed: () => _load(false), child: const Text('加载下一页'))
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
    final rows = data.items
        .where(
          (item) => !LocalStore.instance.userBlocked({
            ...?data.users['${item['author_id']}'],
            ...object(item['author']),
          }, item),
        )
        .toList();
    final indices = {
      for (var i = 0; i < rows.length; i++) '${rows[i]['id']}': i,
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: () async {
          if (widget.primaryReader == null) await widget.loadPrimary(true);
          if (mounted) await _load(true);
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical &&
                notification is ScrollUpdateNotification &&
                widget.active &&
                notification.metrics.extentAfter < 600 &&
                data.hasMore &&
                _reader.error == null) {
              _load(false);
            }
            return false;
          },
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
