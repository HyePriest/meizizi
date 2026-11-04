import '../widgets/adaptive_feed.dart';

import 'package:flutter/material.dart';

import '../widgets/feed_list_item.dart';

import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/thread_thumbnails.dart';
import '../widgets/top_refresh_overlay.dart';
import 'reading_page.dart';

String _heat(dynamic value) {
  final count = number(value);
  if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '$count';
}

class HotTopicsView extends StatefulWidget {
  const HotTopicsView({super.key, this.topic, this.refreshSignal});
  final Json? topic;
  final Listenable? refreshSignal;

  @override
  State<HotTopicsView> createState() => _HotTopicsViewState();
}

class _HotTopicsViewState extends State<HotTopicsView> {
  final _api = TiebaApi();
  final _scroll = ScrollController();
  List<Json> _items = [];
  bool _busy = false, _more = false, _latest = false;
  bool _retryReset = true;
  bool _tapRefreshing = false;
  int _page = 0, _revision = 0;
  String _lastId = '';
  String? _error;
  DateTime? _updated;
  bool get _isTopic => widget.topic != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    widget.refreshSignal?.addListener(_returnToTop);
    LocalStore.instance.addListener(_localChanged);
    _load(reset: true);
  }

  void _localChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _returnToTop() async {
    if (_tapRefreshing) return;
    setState(() => _tapRefreshing = true);
    final motion = _scroll.hasClients
        ? _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          )
        : Future<void>.value();
    try {
      await Future.wait([motion, _load(reset: true, revealAfter: motion)]);
    } finally {
      if (mounted) setState(() => _tapRefreshing = false);
    }
  }

  @override
  void didUpdateWidget(covariant HotTopicsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_returnToTop);
      widget.refreshSignal?.addListener(_returnToTop);
    }
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 500 &&
        _more &&
        !_busy &&
        !_tapRefreshing &&
        _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _revision++;
    widget.refreshSignal?.removeListener(_returnToTop);
    LocalStore.instance.removeListener(_localChanged);
    _scroll.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool reset = false, Future<void>? revealAfter}) async {
    if (_busy && !reset) return;
    final revision = ++_revision;
    final page = reset ? 1 : _page + 1;
    _retryReset = reset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<Json> incoming;
      var more = false;
      var lastId = '';
      if (_isTopic) {
        final result = await _api.topicThreads(
          '${widget.topic!['topic_id']}',
          firstText([widget.topic!['topic_name']]),
          page,
          lastId: reset ? '' : _lastId,
          latest: _latest,
        );
        incoming = result.items;
        more = result.hasMore;
        lastId = result.lastId;
      } else {
        incoming = await _api.hotTopics();
      }
      if (revealAfter != null) await revealAfter;
      if (!mounted || revision != _revision) return;
      setState(() {
        if (reset) _items = [];
        final ids = _items
            .map((p) => '${p[_isTopic ? 'id' : 'topic_id']}')
            .toSet();
        _items.addAll(
          incoming.where((p) => ids.add('${p[_isTopic ? 'id' : 'topic_id']}')),
        );
        _page = page;
        _more = more;
        _lastId = lastId;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is TiebaException ? e.message : '加载失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Widget _topicCard(Json topic, int index) {
    final rank = number(topic['idx_num']);
    final position = rank > 0 ? rank : index + 1;
    final colors = Theme.of(context).colorScheme;
    final description = firstText([topic['topic_desc'], topic['abstract']]);
    return FeedListItem(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('热议话题')),
              body: HotTopicsView(topic: topic),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '$position',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: position <= 3
                        ? colors.error
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstText([topic['topic_name']]),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${_heat(topic['discuss_num'])} 热度',
                      style: TextStyle(color: colors.primary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _threadCard(Json thread) {
    final forum = threadForumName(thread);
    return FeedListItem(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (forum.isNotEmpty)
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingPage(forum: forum),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '$forum吧',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadingPage(
                    threadId: '${thread['id']}',
                    title: firstText([thread['title']]),
                    forum: forum.isEmpty ? null : forum,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstText([thread['title']], '查看帖子'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (firstText([thread['abstract']]).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          plainText(thread['abstract']),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ThreadThumbnails(thread: thread),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Text(
                        '${author(object(thread['author']))} · ${_heat(thread['reply_num'])} 条回复',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _isTopic
        ? _items
              .where(
                (item) =>
                    !LocalStore.instance.hidden(item, object(item['author'])),
              )
              .toList()
        : _items;
    final topic = widget.topic;
    return TopRefreshOverlay(
      refreshing: _tapRefreshing,
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: AdaptiveFeedView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          fullWidthFirst: true,
          fullWidthLast: true,
          itemCount: visible.length + 2,
          itemBuilder: (context, index) {
            if (index == 0)
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic == null
                          ? '贴吧热议榜'
                          : firstText([topic['topic_name']]),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (topic == null)
                      Text(
                        _updated == null
                            ? '看看吧友正在讨论什么'
                            : '更新于 ${_updated!.hour.toString().padLeft(2, '0')}:${_updated!.minute.toString().padLeft(2, '0')} · 下拉刷新',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (topic != null) ...[
                      if (firstText([topic['topic_desc']]).isNotEmpty)
                        Text(firstText([topic['topic_desc']])),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('热门讨论')),
                          ButtonSegment(value: true, label: Text('最新讨论')),
                        ],
                        selected: {_latest},
                        onSelectionChanged: _busy
                            ? null
                            : (values) {
                                if (_latest == values.first) return;
                                setState(() {
                                  _latest = values.first;
                                  _items = [];
                                  _page = 0;
                                  _more = false;
                                });
                                _load(reset: true);
                              },
                      ),
                    ],
                  ],
                ),
              );
            if (index <= visible.length)
              return _isTopic
                  ? _threadCard(visible[index - 1])
                  : _topicCard(visible[index - 1], index - 1);
            return Column(
              children: [
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _load(reset: _retryReset),
                    child: const Text('重试'),
                  ),
                ],
                if (_busy && !_tapRefreshing)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error == null && visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_items.isEmpty ? '暂时没有内容，下拉刷新试试' : '本页内容已被屏蔽'),
                  ),
                if (!_busy && _error == null && _more)
                  TextButton(onPressed: _load, child: const Text('加载更多')),
              ],
            );
          },
        ),
      ),
    );
  }
}
