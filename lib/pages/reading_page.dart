import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../widgets/post_widgets.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/like_button.dart';
import 'reply_page.dart';

class ReadingPage extends StatefulWidget {
  const ReadingPage({
    super.key,
    this.forum,
    this.threadId,
    this.title,
    this.postId,
  });
  final String? forum, threadId, title, postId;
  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  final _api = TiebaApi();
  TiebaPage? _result;
  List<Json> _items = [];
  Map<String, Json> _users = {};
  int _page = 0;
  bool _busy = false, _onlyAuthor = false, _hasMore = true;
  bool _replyOpening = false;
  String? _error;
  String _category = '最新回复';
  int _revision = 0;
  int _viewRevision = 0;
  bool get _isForum => widget.threadId == null;
  bool get _isFloor => widget.postId != null;

  Future<void> _reply([Json? item]) async {
    if (_replyOpening || _busy) return;
    setState(() => _replyOpening = true);
    try {
      Json forum = object(_result?.data['forum']);
      Json thread = object(_result?.data['thread']);
      if (firstText([forum['id'], thread['fid']]).isEmpty) {
        final metadata = await _api.thread(widget.threadId!, 1);
        forum = object(metadata.data['forum']);
        thread = object(metadata.data['thread']);
      }
      final name = firstText([
        forum['name'],
        thread['forum_name'],
        widget.forum,
      ]);
      final id = firstText([forum['id'], thread['fid']]);
      if (name.isEmpty || id.isEmpty) {
        throw const TiebaException('暂时无法获取贴吧信息，请刷新后重试');
      }
      if (!mounted) return;
      final user = item == null
          ? <String, dynamic>{}
          : _users['${item['author_id']}'] ?? object(item['author']);
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReplyPage(
            threadId: widget.threadId!,
            forumName: name,
            forumId: id,
            title: item == null
                ? (_isFloor
                      ? widget.title ?? '回复这一楼'
                      : firstText([thread['title'], widget.title]))
                : '回复 ${author(user)}',
            postId: _isFloor
                ? widget.postId
                : item == null
                ? null
                : '${item['id']}',
            replyUid: item == null
                ? null
                : firstText([user['id'], user['user_id'], item['author_id']]),
          ),
        ),
      );
      if (mounted && sent == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('回复已发送')));
        _load(reset: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is TiebaException ? e.message : '无法打开回复，请稍后重试'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _replyOpening = false);
    }
  }

  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    if (_isForum) {
      LocalStore.instance.visit(widget.forum!).catchError((_) {});
    }
    _load(reset: true);
  }

  void _accountChanged() {
    setState(() {
      _items = [];
      _users = {};
      _result = null;
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy && !reset) {
      return;
    }
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    final next = reset ? 1 : _page + 1;
    try {
      final result = _isForum
          ? await _api.forum(widget.forum!, next, category: _category)
          : _isFloor
          ? await _api.floor(widget.threadId!, widget.postId!, next)
          : await _api.thread(widget.threadId!, next, onlyAuthor: _onlyAuthor);
      if (!mounted || revision != _revision) {
        return;
      }
      setState(() {
        if (reset) _viewRevision++;
        _result = result;
        _page = next;
        _hasMore = result.hasMore;
        final incoming = _isForum
            ? result.threads
            : _isFloor
            ? result.replies
            : result.posts;
        final ids = (reset ? <Json>[] : _items)
            .map((p) => '${p['id']}')
            .toSet();
        _items = [
          if (!reset) ..._items,
          ...incoming.where((p) => ids.add('${p['id']}')),
        ];
        _users = {if (!reset) ..._users, ...result.users};
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = switch (e) {
            TimeoutException() => '请求超时，请检查网络后重试。',
            SocketException() => '无法连接贴吧，请检查网络后重试。',
            TiebaException() => e.message,
            _ => '加载失败，请检查网络后重试。',
          };
        });
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: _isForum
        ? null
        : FloatingActionButton.extended(
            onPressed: _busy || _replyOpening || _result == null
                ? null
                : () => _reply(),
            icon: const Icon(Icons.edit_outlined),
            label: Text(_isFloor ? '回复这一楼' : '写回复'),
          ),
    appBar: AppBar(
      title: Text(
        _isForum
            ? '${widget.forum}吧'
            : _isFloor
            ? '楼中楼'
            : '帖子',
      ),
      actions: [
        if (!_isForum && !_isFloor)
          FilterChip(
            label: const Text('只看楼主'),
            selected: _onlyAuthor,
            onSelected: _busy
                ? null
                : (value) {
                    setState(() {
                      _onlyAuthor = value;
                      _items = [];
                    });
                    _load(reset: true);
                  },
          ),
        IconButton(
          onPressed: _busy ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (_isForum) {
              final forum = object(_result?.data['forum']);
              final sign = object(object(forum['sign_in_info'])['user_info']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ForumAvatar(forum: forum, size: 60),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.forum}吧',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '关注 ${forum['member_num'] ?? 0} · 帖子 ${forum['thread_num'] ?? 0}',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                        SignButton(
                          key: ValueKey('sign-$_page-$_busy'),
                          name: widget.forum!,
                          signed:
                              flag(sign['is_sign_in']) ||
                              flag(forum['is_sign_in']),
                        ),
                      ],
                    ),
                    if (firstText([forum['slogan']]).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('${forum['slogan']}'),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final category in ['最新回复', '最新发布', '热门', '精华'])
                          ChoiceChip(
                            label: Text(category),
                            selected: _category == category,
                            onSelected: _busy
                                ? null
                                : (selected) {
                                    if (!selected || _category == category) {
                                      return;
                                    }
                                    setState(() {
                                      _category = category;
                                      _items = [];
                                      _users = {};
                                      _page = 0;
                                    });
                                    _load(reset: true);
                                  },
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }
            final metadata = object(_result?.data['forum']);
            final thread = object(_result?.data['thread']);
            final name = firstText([
              metadata['name'],
              metadata['forum_name'],
              threadForumName(thread),
              widget.forum,
            ]);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReadingPage(forum: name),
                        ),
                      ),
                      icon: ForumAvatar(forum: metadata, size: 28),
                      label: Text('$name吧'),
                    ),
                  Text(
                    _isFloor
                        ? (widget.title ?? '楼中楼回复')
                        : '${object(_result?.data['thread'])['title'] ?? widget.title ?? ''}',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!_isFloor && _result != null)
                    LikeButton(
                      key: ValueKey('thread-like-$_viewRevision'),
                      threadId: widget.threadId!,
                      data: thread,
                    ),
                ],
              ),
            );
          }
          if (index == _items.length + 1) {
            return _footer(context);
          }
          final item = _items[index - 1];
          final user = _users['${item['author_id']}'] ?? object(item['author']);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _isForum
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReadingPage(
                          threadId: '${item['id']}',
                          title: '${item['title']}',
                          forum: widget.forum,
                        ),
                      ),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserHeader(
                      user: user,
                      subtitle: _isForum
                          ? '发布 ${fullDate(item['create_time'])}'
                          : '${_isFloor ? '' : '${item['floor'] ?? '?'}楼 · '}${fullDate(item['time'] ?? item['create_time'])}',
                    ),
                    const SizedBox(height: 10),
                    if (_isForum) ...[
                      Text(
                        '${number(item['is_top']) == 1 ? '置顶 · ' : ''}${item['title'] ?? ''}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        objects(item['abstract'])
                            .map((p) => p['text'] ?? '')
                            .join(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${item['reply_num'] ?? 0} 条回复',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ] else ...[
                      PostContent(parts: objects(item['content'])),
                      LikeButton(
                        key: ValueKey('like-$_viewRevision-${item['id']}'),
                        threadId: widget.threadId!,
                        postId: '${item['id']}',
                        comment: _isFloor,
                        data: item,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _busy || _replyOpening
                              ? null
                              : () => _reply(item),
                          icon: const Icon(Icons.reply, size: 18),
                          label: const Text('回复'),
                        ),
                      ),
                      if (number(item['sub_post_number']) > 0) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReadingPage(
                                threadId: widget.threadId,
                                postId: '${item['id']}',
                                title: '${item['floor']}楼的回复',
                                forum: firstText([
                                  object(_result?.data['forum'])['name'],
                                  widget.forum,
                                ]),
                              ),
                            ),
                          ),
                          child: Text('查看 ${item['sub_post_number']} 条楼中楼回复'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  Widget _footer(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _load(reset: _items.isEmpty),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂时没有可显示的内容')),
      );
    }
    return Center(
      child: _hasMore
          ? TextButton(onPressed: _load, child: const Text('加载下一页'))
          : const Padding(padding: EdgeInsets.all(24), child: Text('已经到底了')),
    );
  }
}
