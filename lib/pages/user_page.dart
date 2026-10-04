import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import '../widgets/thread_thumbnails.dart';
import 'reading_page.dart';
import 'user_connections_page.dart';

void openUser(BuildContext context, Json user) {
  if (firstText([user['id'], user['user_id'], user['portrait']]).isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => UserPage(user: user)));
}

class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.user});
  final Json user;
  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _api = TiebaApi();
  Json _user = {};
  List<Json> _posts = [];
  bool _busy = false, _more = true;
  int _page = 0;
  String? _error;
  void _openConnections(UserConnections kind) {
    final uid = firstText([_user['id'], _user['user_id']]);
    if (uid.isEmpty || uid == '0') return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserConnectionsPage(uid: uid, kind: kind),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load(reset: true);
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (reset) {
        final result = await _api.userProfile(widget.user);
        if (!mounted) return;
        setState(() {
          _user = {...widget.user, ...object(result.data['user'])};
          _posts = [];
          _page = 0;
        });
      }
      final uid = firstText([_user['id'], _user['user_id']]);
      if (uid.isEmpty || uid == '0') throw const TiebaException('暂时无法获取该用户的主页');
      final result = await _api.userPosts(uid, _page + 1);
      if (!mounted) return;
      final incoming = objects(result.data['post_list']);
      setState(() {
        final seen = _posts
            .map((p) => firstText([p['thread_id'], p['tid'], p['id']]))
            .toSet();
        _posts.addAll(
          incoming.where(
            (p) => seen.add(firstText([p['thread_id'], p['tid'], p['id']])),
          ),
        );
        _page++;
        _more = result.data.containsKey('has_more')
            ? flag(result.data['has_more'])
            : incoming.length >= 20;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is TiebaException ? e.message : '主页加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('用户主页')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              UserAvatar(user: _user, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author(_user),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('主题帖 ${_user['thread_num'] ?? 0}'),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _openConnections(UserConnections.follows),
                child: Text('关注 ${_user['concern_num'] ?? 0}'),
              ),
              TextButton(
                onPressed: () => _openConnections(UserConnections.fans),
                child: Text('粉丝 ${_user['fans_num'] ?? 0}'),
              ),
              TextButton(
                onPressed: () => _openConnections(UserConnections.forums),
                child: const Text('关注的吧'),
              ),
            ],
          ),
          if (firstText([_user['intro']]).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${_user['intro']}'),
            ),
          const SizedBox(height: 16),
          Text('主题帖', style: Theme.of(context).textTheme.titleMedium),
          for (final post in _posts)
            Card(
              child: InkWell(
                onTap: () {
                  final tid = firstText([
                    post['thread_id'],
                    post['tid'],
                    post['id'],
                  ]);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingPage(
                        threadId: tid,
                        title: firstText([post['title']]),
                        forum: threadForumName(post),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstText([post['title']], '查看帖子'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${threadForumName(post)}吧 · ${relativeDate(post['create_time'] ?? post['time'])}',
                      ),
                      ThreadThumbnails(thread: post),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
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
            ),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_more && _error == null)
            TextButton(onPressed: _load, child: const Text('加载更多'))
          else if (_posts.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('没有可公开查看的主题帖'),
            ),
        ],
      ),
    ),
  );
}
