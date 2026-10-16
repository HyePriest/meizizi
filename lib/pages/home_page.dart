import '../widgets/app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/post_widgets.dart';
import '../widgets/thread_thumbnails.dart';
import 'user_page.dart';
import '../widgets/bulk_sign_dialog.dart';
import 'reading_page.dart';
import 'search_page.dart';
import 'login_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = TiebaApi();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<Json> _items = [];
  Map<String, Json> _users = {};
  int _tab = 0, _page = 0, _revision = 0;
  bool _busy = false, _hasMore = true;
  String? _error;
  final Map<
    int,
    ({
      List<Json> items,
      Map<String, Json> users,
      int page,
      bool more,
      String? error,
      double offset,
    })
  >
  _savedTabs = {};

  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_authChanged);
    LocalStore.instance.addListener(_localChanged);
    _scroll.addListener(_loadNearEnd);
    _load(reset: true);
  }

  void _authChanged() {
    _savedTabs.clear();
    setState(() {
      _items = [];
      _users = {};
      _page = 0;
    });
    if (_tab != 2) {
      _load(reset: true);
    } else {
      setState(() {
        _items = [];
        _users = {};
        _page = 0;
      });
    }
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
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_busy &&
        _hasMore &&
        _error == null &&
        _tab != 2) {
      _load();
    }
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_authChanged);
    LocalStore.instance.removeListener(_localChanged);
    _api.close();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_tab == 2 || (_busy && !reset)) return;
    final revision = ++_revision, tab = _tab, next = reset ? 1 : _page + 1;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<Json> incoming;
      Map<String, Json> users = {};
      bool hasMore;
      if (tab == 1) {
        if (!AuthStore.instance.isLoggedIn) {
          if (mounted && revision == _revision) {
            setState(() {
              _busy = false;
              _hasMore = false;
            });
          }
          return;
        }
        final result = await _api.followedForums(next);
        incoming = result.items;
        hasMore = result.hasMore;
      } else {
        final result = await _api.home(next);
        incoming = result.threads
            .where((t) => !t.containsKey('lego_card'))
            .toList();
        users = result.users;
        hasMore = result.data.containsKey('has_more')
            ? flag(result.data['has_more'])
            : result.data.containsKey('page')
            ? result.hasMore
            : result.threads.isNotEmpty;
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        if (reset) {
          _items = [];
          _users = {};
        }
        final ids = _items
            .map((p) => tab == 1 ? forumName(p) : '${p['id']}')
            .toSet();
        _items.addAll(
          incoming.where(
            (p) => ids.add(tab == 1 ? forumName(p) : '${p['id']}'),
          ),
        );
        _users.addAll(users);
        _page = next;
        _hasMore = hasMore;
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is TiebaException ? e.message : '加载失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadNearEnd();
        });
      }
    }
  }

  void _open(String name) {
    if (name.trim().isEmpty) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReadingPage(forum: name)));
  }

  void _openPost(Json item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReadingPage(
        threadId: '${item['id']}',
        title: '${item['title'] ?? ''}',
        forum: threadForumName(item).isEmpty ? null : threadForumName(item),
      ),
    ),
  );
  void _searchFor(String raw) {
    final word = raw.trim();
    if (word.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => SearchPage(word: word)));
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
    try {
      if (choice == 'forum') {
        await LocalStore.instance.blockForum(threadForumName(item));
      } else {
        await LocalStore.instance.blockUser(userKey(user, item), author(user));
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('已屏蔽，可在“我”中管理')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('屏蔽保存失败，请重试')));
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
    final summary = objects(item['abstract'])
        .map((p) => p['text'] ?? '')
        .join();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: forum.isEmpty ? null : () => _open(forum),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ForumAvatar(
                    forum: {
                      ...object(item['forum']),
                      ...object(item['forum_info']),
                      'name': forum,
                      'avatar': firstText([
                        object(item['forum_info'])['avatar'],
                        object(item['forum'])['avatar'],
                        item['forum_avatar'],
                      ]),
                    },
                    size: 42,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          forum.isEmpty ? '所属吧信息暂不可用' : '$forum吧',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          threadTimeLabel(item),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: TextButton.icon(
                        onPressed: () => openUser(context, user),
                        icon: UserAvatar(user: user, size: 20),
                        label: Text(
                          author(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => _openPost(item),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstText([item['title']], '查看帖子'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ThreadThumbnails(thread: item),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _openPost(item),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: Text('${item['reply_num'] ?? 0} 条回复'),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: '屏蔽内容',
                  icon: const Icon(Icons.close, size: 20),
                  onSelected: (choice) => _block(choice, item, user),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'forum',
                      enabled: forum.isNotEmpty,
                      child: Text(forum.isEmpty ? '无法取得所属吧' : '屏蔽 $forum吧'),
                    ),
                    PopupMenuItem(
                      value: 'user',
                      enabled: userKey(user, item).isNotEmpty,
                      child: Text('屏蔽 ${author(user)}'),
                    ),
                  ],
                ),
              ],
            ),
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
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        controller: _scroll,
        key: ValueKey(_tab),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_tab == 1) ...[
            if (LocalStore.instance.recent.isNotEmpty) ...[
              Text('最近浏览', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final name in LocalStore.instance.recent)
                    ActionChip(
                      label: Text('$name吧'),
                      onPressed: () => _open(name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
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
                        task.allSigned ? Icons.check : Icons.event_available,
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
                          height: MediaQuery.sizeOf(context).height * .65,
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
                      onPressed: () => Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                      child: const Text('登录'),
                    ),
                  ],
                ),
              ),
          ],
          ...visible.map(_entry),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _load(reset: _items.isEmpty),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (_busy)
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _tab == 2
        ? AppBar(
            title: const Text('我的'),
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
        : AppBar(
            titleSpacing: 12,
            title: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: _searchFor,
              decoration: InputDecoration(
                hintText: '搜索吧或帖子',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: IconButton(
                  onPressed: () => _searchFor(_search.text),
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
    body: _tab == 2 ? const ProfilePage() : _content(),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) {
        if (_tab == tab) return;
        FocusScope.of(context).unfocus();
        if (_tab != 2) {
          _savedTabs[_tab] = (
            items: List.of(_items),
            users: Map.of(_users),
            page: _page,
            more: _hasMore,
            error: _error,
            offset: _scroll.hasClients ? _scroll.offset : 0,
          );
        }
        final saved = _savedTabs[tab];
        setState(() {
          _tab = tab;
          _revision++;
          _busy = false;
          _items = saved?.items ?? [];
          _users = saved?.users ?? {};
          _page = saved?.page ?? 0;
          _hasMore = saved?.more ?? true;
          _error = saved?.error;
        });
        if (tab != 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) {
              _scroll.jumpTo(
                (saved?.offset ?? 0).clamp(0, _scroll.position.maxScrollExtent),
              );
            }
          });
          if (saved == null || saved.page == 0) _load(reset: true);
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: '我的吧',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '我的',
        ),
      ],
    ),
  );
}
