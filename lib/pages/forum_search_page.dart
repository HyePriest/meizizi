import '../widgets/adaptive_feed.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../widgets/forum_thread_card.dart';

class ForumSearchPage extends StatefulWidget {
  const ForumSearchPage({
    super.key,
    required this.name,
    this.api,
    this.levelNames = const {},
  });
  final String name;
  final TiebaApi? api;
  final Map<int, String> levelNames;

  @override
  State<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends State<ForumSearchPage> {
  late final _api = widget.api ?? TiebaApi();
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _items = <Json>[];
  String _word = '';
  String? _error;
  bool _busy = false, _more = false;
  int _page = 0, _revision = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
  }

  void _nearEnd() {
    if (_scroll.position.extentAfter < 500 &&
        _more &&
        !_busy &&
        _error == null) {
      _load();
    }
  }

  void _search() {
    final word = _query.text.trim();
    if (word.isEmpty) return;
    FocusScope.of(context).unfocus();
    _word = word;
    _load(reset: true);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load({bool reset = false}) async {
    if (_word.isEmpty || (_busy && !reset)) return;
    final revision = ++_revision;
    final word = _word;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 0;
        _more = false;
      }
    });
    try {
      final result = await _api.searchForum(widget.name, word, page);
      if (!mounted || revision != _revision) return;
      final ids = _items.map((post) => '${post['tid']}').toSet();
      setState(() {
        _items.addAll(
          result.items
              .where((post) => ids.add('${post['tid']}'))
              .map(
                (post) => {
                  ...post,
                  'id': firstText([post['tid'], post['thread_id'], post['id']]),
                  'title': plainText(post['title']),
                  'forum_name': widget.name,
                  'abstract': contentParts(post['content']),
                  'reply_num': post['reply_num'] ?? post['post_num'],
                  'agree_num': post['agree_num'] ?? post['like_num'],
                  // Search does not report this account's vote state.
                  '_agree_uncertain': 1,
                },
              ),
        );
        _page = page;
        _more = result.hasMore;
      });
      unawaited(_loadDetails(revision));
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = error is TiebaException ? error.message : '搜索失败，请稍后重试';
        });
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _loadDetails(int revision) async {
    final pending = _items
        .where((post) => !flag(post['_feed_details_loaded']))
        .map((post) => '${post['id']}')
        .toList();
    for (var start = 0; start < pending.length; start += 3) {
      if (!mounted || revision != _revision) return;
      await Future.wait(
        pending.skip(start).take(3).map((id) async {
          try {
            final details = await _api.threadFeedDetails(id);
            if (!mounted || revision != _revision) return;
            final index = _items.indexWhere((post) => post['id'] == id);
            if (index < 0) return;
            details['author'] = {
              ...object(_items[index]['author']),
              ...object(details['author']),
            };
            // Keep any vote that the user has already synchronized or changed.
            if (!flag(_items[index]['_agree_uncertain'])) {
              details.remove('agree');
              details.remove('agree_num');
            }
            setState(() => _items[index] = {..._items[index], ...details});
          } catch (_) {
            // Missing counts stay unknown instead of being displayed as zero.
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _revision++;
    if (widget.api == null) _api.close();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _footer() {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_error!),
            TextButton(
              onPressed: () => _load(reset: _page == 0),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_word.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            const Icon(Icons.search, size: 40),
            const SizedBox(height: 12),
            Text('搜索${widget.name}吧的帖子'),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('本吧没有找到相关帖子')),
      );
    }
    return Center(
      child: _more
          ? TextButton(onPressed: _load, child: const Text('加载更多'))
          : const Padding(padding: EdgeInsets.all(20), child: Text('没有更多结果了')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: TextField(
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: '搜索${widget.name}吧',
          border: InputBorder.none,
        ),
      ),
      actions: [TextButton(onPressed: _search, child: const Text('搜索'))],
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: AdaptiveFeedView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        fullWidthLast: true,
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) return _footer();
          final post = _items[index];
          return ForumThreadCard(
            key: ValueKey(post['id']),
            thread: post,
            user: object(post['author']),
            forum: widget.name,
            levelNames: widget.levelNames,
            onLikeChanged: (source, patch) {
              if (!mounted) return;
              setState(() {
                final index = _items.indexWhere(
                  (item) => item['id'] == source['id'],
                );
                if (index >= 0) _items[index] = {..._items[index], ...patch};
              });
            },
          );
        },
      ),
    ),
  );
}
