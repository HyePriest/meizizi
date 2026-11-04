import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/share_content.dart';
import '../data/tieba_api.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/home_thread_card.dart';
import '../widgets/liquid_feed_switcher.dart';
import '../widgets/post_widgets.dart';
import 'reading_page.dart';
import 'user_page.dart';

class _SearchBucket {
  List<Json> items = [];
  bool busy = false, loaded = false, more = false, retryReset = true;
  int page = 0, revision = 0;
  String? error;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.word});
  final String word;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _api = TiebaApi();
  final _cache = <String, Map<int, _SearchBucket>>{};
  final _scrolls = List.generate(4, (_) => ScrollController());
  late final TextEditingController _query;
  late String _word;
  String _likeAccount = AuthStore.instance.activeId;
  int _tab = 0;
  Map<int, _SearchBucket> get _buckets => _cache.putIfAbsent(
    _word,
    () => {for (var i = 1; i <= 3; i++) i: _SearchBucket()},
  );

  @override
  void initState() {
    super.initState();
    _word = widget.word.trim();
    _query = TextEditingController(text: _word);
    LocalStore.instance.addListener(_localChanged);
    AuthStore.instance.addListener(_accountChanged);
    for (var i = 0; i < 4; i++) {
      final index = i;
      _scrolls[i].addListener(() => _nearEnd(index));
    }
    _startSearch();
  }

  void _startSearch() {
    for (var i = 1; i <= 3; i++) {
      final bucket = _buckets[i]!;
      if (!bucket.loaded && !bucket.busy && bucket.error == null) _load(i);
    }
  }

  @override
  void dispose() {
    LocalStore.instance.removeListener(_localChanged);
    AuthStore.instance.removeListener(_accountChanged);
    _api.close();
    _query.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  String _identity(int kind, Json item) => kind == 1
      ? firstText([item['name'], item['forum_id']])
      : kind == 3
      ? firstText([item['id'], item['portrait']])
      : '${firstText([item['tid'], item['thread_id'], item['id']])}:${firstText([item['pid'], item['post_id']])}';

  Future<void> _load(int kind, {bool reset = false}) async {
    if (_word.isEmpty) return;
    final word = _word;
    final bucket = _buckets[kind]!;
    if (bucket.busy && !reset) return;
    final revision = ++bucket.revision;
    final page = reset ? 1 : bucket.page + 1;
    setState(() {
      bucket.busy = true;
      bucket.error = null;
      bucket.retryReset = reset;
    });
    try {
      final result = kind == 3
          ? await _api.searchUsers(word, page)
          : await _api.search(word, page, forums: kind == 1);
      if (!mounted || revision != bucket.revision) return;
      if (reset) bucket.items = [];
      final seen = bucket.items.map((item) => _identity(kind, item)).toSet();
      bucket.items.addAll(
        result.items
            .where((item) => seen.add(_identity(kind, item)))
            .map((item) => kind == 2 ? _postData(item) : item),
      );
      bucket.page = page;
      bucket.more = result.hasMore;
      bucket.loaded = true;
    } catch (e) {
      if (!mounted || revision != bucket.revision) return;
      bucket.error = e is TiebaException ? e.message : '搜索失败，请检查网络后重试';
    } finally {
      if (revision == bucket.revision) {
        bucket.busy = false;
        if (mounted && word == _word) setState(() {});
      }
    }
  }

  void _nearEnd(int index) {
    if (_tab != index ||
        !_scrolls[index].hasClients ||
        _scrolls[index].position.extentAfter > 500)
      return;
    final kind = index == 0 ? 2 : index;
    final bucket = _buckets[kind]!;
    if (bucket.more && !bucket.busy && bucket.error == null) _load(kind);
  }

  void _select(int index) {
    if (_tab == index) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = index);
    if (index != 0) {
      final bucket = _buckets[index]!;
      if (!bucket.loaded && !bucket.busy && bucket.error == null) _load(index);
    }
  }

  void _search() {
    final word = _query.text.trim();
    if (word.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (word == _word) {
      _refresh();
      return;
    }
    setState(() {
      _word = word;
      _tab = 0;
    });
    for (final scroll in _scrolls) {
      if (scroll.hasClients) scroll.jumpTo(0);
    }
    if (_cache.length > 5) {
      _cache.remove(_cache.keys.firstWhere((key) => key != _word));
    }
    _startSearch();
  }

  Future<void> _refresh() async {
    if (_tab == 0) {
      await Future.wait([for (var i = 1; i <= 3; i++) _load(i, reset: true)]);
    } else {
      await _load(_tab, reset: true);
    }
  }

  Widget _forum(Json item) {
    final name = plainText(item['name']);
    final brief = plainText(item['brief']).trim();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: UserAvatar(user: {'avatar': item['img']}, size: 44),
      title: Text(
        '$name吧',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (brief.isNotEmpty)
            Text(brief, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${item['member'] ?? 0} 人关注 · ${item['post'] ?? 0} 个帖子',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => ReadingPage(forum: name))),
    );
  }

  Widget _user(Json user) {
    final intro = plainText(user['intro']).trim();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: UserAvatar(user: user, size: 44),
      title: Text(
        author(user),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        intro.isEmpty ? '${user['fans_num'] ?? 0} 粉丝' : intro,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => openUser(context, user),
    );
  }

  Json _postData(Json item) => {
    ...item,
    'id': firstText([item['tid'], item['thread_id'], item['id']]),
    'title': plainText(item['title']),
    'forum_name': plainText(item['forum_name']),
    'author': object(item['user']),
    'abstract': contentParts(item['content']),
    'reply_num': number(item['post_num']),
    'agree_num': number(item['like_num']),
    // Search returns the total likes, but does not return this account's vote.
    '_agree_uncertain': 1,
  };

  void _localChanged() {
    if (mounted) setState(() {});
  }

  void _accountChanged() {
    final account = AuthStore.instance.activeId;
    if (!mounted || _likeAccount == account) return;
    _likeAccount = account;
    setState(() {
      for (final buckets in _cache.values) {
        final bucket = buckets[2];
        if (bucket == null) continue;
        bucket.items = [
          for (final item in bucket.items)
            {...item, 'agree': null, 'has_agree': 0, '_agree_uncertain': 1},
        ];
      }
    });
  }

  List<Json> _visibleItems(int kind) => kind == 2
      ? _buckets[kind]!.items
            .where(
              (item) =>
                  !LocalStore.instance.hidden(item, object(item['author'])),
            )
            .toList()
      : _buckets[kind]!.items;

  void _updateLike(Json source, Json patch) {
    if (!mounted) return;
    setState(() {
      for (final buckets in _cache.values) {
        final bucket = buckets[2];
        if (bucket == null) continue;
        bucket.items = [
          for (final item in bucket.items)
            if (item['id'] == source['id']) {...item, ...patch} else item,
        ];
      }
    });
  }

  void _openPost(Json item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReadingPage(
        previewThread: item,
        threadId: '${item['id']}',
        targetPostId: number(item['pid'] ?? item['post_id']) > 0
            ? '${item['pid'] ?? item['post_id']}'
            : null,
        title: '${item['title']}',
        forum: firstText([item['forum_name']]).isEmpty
            ? null
            : '${item['forum_name']}',
      ),
    ),
  );

  Future<void> _sharePost(Json item) async {
    try {
      await ShareContent.post(
        threadId: '${item['id']}',
        title: '${item['title']}',
        forum: threadForumName(item),
        post: item,
      ).share();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('无法打开分享，请稍后重试')));
      }
    }
  }

  Future<void> _block(String choice, Json item) async {
    try {
      if (choice == 'forum') {
        await LocalStore.instance.blockForum(threadForumName(item));
      } else {
        final user = object(item['author']);
        await LocalStore.instance.blockUser(userKey(user, item), author(user));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('屏蔽保存失败，请重试')));
      }
    }
  }

  Widget _post(Json item) => HomeThreadCard(
    key: ValueKey(_identity(2, item)),
    thread: item,
    user: object(item['author']),
    onOpenForum: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReadingPage(forum: threadForumName(item)),
      ),
    ),
    onOpen: () => _openPost(item),
    onShare: () => _sharePost(item),
    onBlock: (choice) => _block(choice, item),
    onLikeChanged: _updateLike,
  );

  Widget _entry(int kind, Json item) => kind == 1
      ? _forum(item)
      : kind == 3
      ? _user(item)
      : _post(item);

  Widget _footer(int kind, {bool preview = false}) {
    final bucket = _buckets[kind]!;
    if (bucket.error != null)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                bucket.error!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () => _load(kind, reset: bucket.retryReset),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    if (bucket.busy)
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    if (_visibleItems(kind).isEmpty)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          '没有找到相关${kind == 1
              ? '吧'
              : kind == 3
              ? '用户'
              : '帖子'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    if (preview) return const SizedBox.shrink();
    return Center(
      child: bucket.more
          ? TextButton(onPressed: () => _load(kind), child: const Text('加载更多'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '没有更多结果了',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
    );
  }

  Widget _heading(String title, int kind) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (kind != 2)
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => _select(kind),
            child: const Text('查看全部'),
          ),
      ],
    ),
  );

  Widget _overview() {
    final rows = <WidgetBuilder>[];
    for (final kind in [1, 3, 2]) {
      final bucket = _buckets[kind]!;
      rows.add(
        (_) => _heading(
          kind == 1
              ? '相关吧'
              : kind == 3
              ? '相关用户'
              : '相关帖子',
          kind,
        ),
      );
      final items = kind == 2 ? _visibleItems(kind) : bucket.items.take(2);
      for (final item in items) {
        rows.add((_) => _entry(kind, item));
        if (kind != 2) rows.add((_) => const Divider(height: 1));
      }
      rows.add((_) => _footer(kind, preview: kind != 2));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrolls[0],
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: rows.length,
        itemBuilder: (context, index) => rows[index](context),
      ),
    );
  }

  Widget _category(int kind) {
    final items = _visibleItems(kind);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrolls[kind],
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          kind == 2 ? 12 : 16,
          4,
          kind == 2 ? 12 : 16,
          24,
        ),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) =>
            kind == 2 ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (_, index) =>
            index == items.length ? _footer(kind) : _entry(kind, items[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: SafeArea(
      bottom: false,
      child: LiquidFeedSwitcher(
        key: ValueKey(_word),
        header: SizedBox(
          height: 48,
          child: AppBar(
            primary: false,
            toolbarHeight: 48,
            titleSpacing: 0,
            title: SizedBox(
              height: 36,
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            actions: [TextButton(onPressed: _search, child: const Text('搜索'))],
          ),
        ),
        labels: const ['综合', '吧', '帖子', '用户'],
        selected: _tab,
        onSelected: _select,
        onSwitching: (switching) {
          if (switching) FocusScope.of(context).unfocus();
        },
        children: [_overview(), for (var i = 1; i <= 3; i++) _category(i)],
      ),
    ),
  );
}
