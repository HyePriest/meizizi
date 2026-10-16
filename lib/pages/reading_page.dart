import '../widgets/app_snack_bar.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/share_content.dart';
import '../widgets/comment_card.dart';
import '../widgets/post_widgets.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/like_button.dart';
import '../widgets/forum_thread_card.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_action_bar.dart';
import 'reply_page.dart';
import 'login_page.dart';

class ReadingPage extends StatefulWidget {
  const ReadingPage({
    super.key,
    this.forum,
    this.threadId,
    this.title,
    this.postId,
    this.parentPost,
    this.api,
    this.levelNames = const {},
  });
  final String? forum, threadId, title, postId;
  final Json? parentPost;
  final TiebaApi? api;
  final Map<int, String> levelNames;
  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  late final TiebaApi _api;
  TiebaPage? _result;
  List<Json> _items = [];
  List<Json> _pinned = [];
  final _sortAnchor = GlobalKey();
  Map<String, Json> _users = {};
  Json _thread = {}, _forum = {};
  Json _parentPost = {};
  final _confirmedVotes = <String>{};
  Map<int, String> _levelNames = {};
  final _scroll = ScrollController();
  int _page = 0;
  bool _busy = false, _onlyAuthor = false, _hasMore = true;
  bool _replyOpening = false;
  bool _hot = false, _following = false, _followUncertain = false;
  String? _error;
  String _category = '最新回复';
  int _revision = 0;
  int _viewRevision = 0;
  bool get _isForum => widget.threadId == null;
  bool get _isFloor => widget.postId != null;
  void _openFloor(Json item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReadingPage(
        threadId: widget.threadId,
        postId: '${item['id']}',
        title: firstText([_thread['title'], widget.title]),
        forum: firstText([_forum['name'], widget.forum]),
        levelNames: _levelNames,
        parentPost: {
          ...item,
          'author': {
            ...?_users['${item['author_id']}'],
            ...object(item['author']),
          },
        },
      ),
    ),
  );
  Future<void> _changeSort(bool hot) async {
    if (hot == _hot || _busy) return;
    final anchor = _sortAnchor.currentContext?.findRenderObject() as RenderBox?;
    final before = anchor?.localToGlobal(Offset.zero).dy;
    final offset = _scroll.hasClients ? _scroll.offset : null;
    setState(() => _hot = hot);
    await _load(reset: true, preserveFirst: true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current =
          _sortAnchor.currentContext?.findRenderObject() as RenderBox?;
      final after = current?.localToGlobal(Offset.zero).dy;
      final target = before != null && after != null
          ? _scroll.offset + after - before
          : offset;
      if (target != null && (target - _scroll.offset).abs() > 0.5) {
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  bool get _followed =>
      AuthStore.instance.isLoggedIn &&
      (flag(_forum['is_like']) || flag(_forum['is_liked']));

  void _loadNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_busy &&
        _hasMore &&
        _error == null) {
      _load();
    }
  }

  Future<void> _follow() async {
    if (_following || _followUncertain || _busy) return;
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    final id = firstText([_forum['id']]);
    if (id.isEmpty) return;
    final account = AuthStore.instance.activeId;
    final undo = _followed;
    setState(() => _following = true);
    try {
      await _api.followForum(widget.forum!, id, undo: undo);
      if (!mounted || AuthStore.instance.activeId != account) return;
      setState(() {
        _forum['is_like'] = undo ? 0 : 1;
        _forum['is_liked'] = undo ? 0 : 1;
      });
      await _load(reset: true);
    } catch (e) {
      if (mounted && AuthStore.instance.activeId == account) {
        if (e is TiebaException && e.uncertain) {
          setState(() => _followUncertain = true);
        }
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              e is TiebaException
                  ? (e.uncertain ? '关注结果未确认，请刷新核对' : e.message)
                  : '关注操作失败，请重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

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
            .showAppSnackBar(const AppSnackBar(content: Text('回复已发送')));
        _load(reset: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
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
    _api = widget.api ?? TiebaApi();
    _parentPost = {...?widget.parentPost};
    _levelNames = {...widget.levelNames};
    AuthStore.instance.addListener(_accountChanged);
    LocalStore.instance.addListener(_preferencesChanged);
    _scroll.addListener(_loadNearEnd);
    if (_isForum) {
      LocalStore.instance.visit(widget.forum!).catchError((_) {});
    }
    _load(reset: true);
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  bool _blocked(Json item) => LocalStore.instance.userBlocked({
    ...?_users['${item['author_id']}'],
    ...object(item['author']),
  }, item);

  void _accountChanged() {
    setState(() {
      _items = [];
      _pinned = [];
      _users = {};
      _result = null;
      _thread = {};
      _forum = {};
      _levelNames = {};
      _followUncertain = false;
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    LocalStore.instance.removeListener(_preferencesChanged);
    _api.close();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false, bool preserveFirst = false}) async {
    if (_busy && !reset) {
      return;
    }
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    final next = reset ? 1 : _page + 1;
    final previousFirst = preserveFirst
        ? _items.where((p) => number(p['floor']) == 1).toList()
        : <Json>[];
    try {
      final result = _isForum
          ? await _api.forum(widget.forum!, next, category: _category)
          : _isFloor
          ? await _api.floor(widget.threadId!, widget.postId!, next)
          : await _api.thread(
              widget.threadId!,
              next,
              onlyAuthor: _onlyAuthor,
              hot: _hot,
              onFloorNumbers: (floors) {
                if (!mounted || !_hot) return;
                setState(() {
                  for (final post in _items) {
                    final floor = floors['${post['id']}'];
                    if (floor != null) {
                      if (floor > 0) post['floor'] = floor;
                      post['floor_pending'] = false;
                    }
                  }
                });
              },
            );
      if (!mounted || revision != _revision) {
        return;
      }
      final unsupportedHot =
          !_isForum &&
          !_isFloor &&
          _hot &&
          number(result.data['sort_type']) != 2;
      setState(() {
        if (unsupportedHot) _hot = false;
        if (reset && !preserveFirst) _viewRevision++;
        _result = result;
        if (_isFloor && object(result.data['post']).isNotEmpty) {
          final parent = object(result.data['post']);
          _parentPost = {
            ..._parentPost,
            ...parent,
            'author': {
              ...object(_parentPost['author']),
              ...object(parent['author']),
            },
          };
        }
        if (reset || _forum.isEmpty) _forum = object(result.data['forum']);
        if ((reset && !preserveFirst) || _thread.isEmpty) {
          _thread = object(result.data['thread']);
        }
        if (reset) _followUncertain = false;
        _page = next;
        _hasMore = result.hasMore;
        var incoming = _isForum
            ? result.threads
            : _isFloor
            ? result.replies
            : result.posts;
        if (_isForum) {
          final pins = (reset ? <Json>[] : _pinned)
            ..addAll(incoming.where((p) => flag(p['is_top'])));
          final pinIds = <String>{};
          _pinned = pins.where((p) => pinIds.add('${p['id']}')).toList();
          incoming = incoming.where((p) => !flag(p['is_top'])).toList();
        }
        if (previousFirst.isNotEmpty) {
          incoming = [
            ...previousFirst,
            ...incoming.where(
              (p) =>
                  number(p['floor']) != 1 &&
                  !previousFirst.any((old) => old['id'] == p['id']),
            ),
          ];
        }
        final ids = (reset ? <Json>[] : _items)
            .map((p) => '${p['id']}')
            .toSet();
        _items = [
          if (!reset) ..._items,
          ...incoming.where((p) => ids.add('${p['id']}')),
        ];
        if (_isForum && _category == '最新回复') {
          _items.sort((a, b) => lastReplyTime(b).compareTo(lastReplyTime(a)));
        }
        if (_isForum && _category == '最新发布') {
          _items.sort(
            (a, b) =>
                number(b['create_time']).compareTo(number(a['create_time'])),
          );
        }
        if (!_isForum && !_isFloor) {
          // A first-floor like is the thread like; keep a single authoritative record.
          for (final post in _items.where((p) => number(p['floor']) == 1)) {
            if (_thread['agree'] is! Map && post['agree'] is Map) {
              _thread['agree'] = post['agree'];
            }
          }
          _items = [
            ..._items.where((p) => number(p['floor']) == 1),
            ..._items.where((p) => number(p['floor']) != 1),
          ];
        }
        _users = {if (!reset) ..._users, ...result.users};
      });
      if (reset && !_isForum && !_isFloor) {
        LocalStore.instance
            .visitThread(
              widget.threadId!,
              firstText([_thread['title'], widget.title]),
              firstText([_forum['name'], widget.forum]),
            )
            .catchError((_) {});
      }
      if (unsupportedHot) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          const AppSnackBar(content: Text('该帖暂不支持热度排序，已按楼层显示')),
        );
      }
      if (reset && !preserveFirst && firstText([_forum['id']]).isNotEmpty) {
        try {
          final levels = await _api.forumLevels('${_forum['id']}');
          if (mounted && revision == _revision) {
            setState(
              () => _levelNames = {
                for (final level in objects(levels['level_info']))
                  number(level['id']): firstText([level['name']]),
              },
            );
          }
        } catch (_) {
          /* The post remains readable if titles cannot be loaded. */
        }
      }
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

  ShareContent _shareContent([Json? item]) => ShareContent.post(
    threadId: widget.threadId!,
    title: firstText([_thread['title'], widget.title]),
    forum: firstText([_forum['name'], widget.forum]),
    postId: item == null ? '' : (_isFloor ? widget.postId! : '${item['id']}'),
    comment: item == null
        ? null
        : {
            ...item,
            'author': {
              ...?_users['${item['author_id']}'],
              ...object(item['author']),
            },
          },
  );

  Future<void> _share([Json? item]) async {
    try {
      await _shareContent(item).share();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showAppSnackBar(const AppSnackBar(content: Text('无法打开分享，请使用复制链接')));
      }
    }
  }

  Future<void> _copyLink(Json item) async {
    await _shareContent(item).copyLink();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showAppSnackBar(const AppSnackBar(content: Text('链接已复制')));
    }
  }

  Future<void> _blockUser(Json item) async {
    final user = {
      ...?_users['${item['author_id']}'],
      ...object(item['author']),
    };
    final key = userKey(user, item);
    if (key.isEmpty) return;
    try {
      await LocalStore.instance.blockUser(key, author(user));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showAppSnackBar(
        AppSnackBar(
          content: Text('已拉黑 ${author(user)}，本机隐藏其帖子和评论'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => LocalStore.instance.unblock(key, forum: false),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('拉黑保存失败，请重试')));
      }
    }
  }

  Future<void> _refreshPoll() async {
    final account = AuthStore.instance.activeId;
    final result = await _api.thread(widget.threadId!, 1);
    if (!mounted || account != AuthStore.instance.activeId) return;
    final poll = object(object(result.data['thread'])['poll_info']);
    if (poll.isEmpty) throw const TiebaException('票数暂时不可用，请稍后刷新');
    setState(() => _thread = {..._thread, 'poll_info': poll});
  }

  Widget _commentCard(Json item, {bool parent = false}) {
    final nested = _isFloor && !parent;
    final isFirstFloor = !nested && number(item['floor']) == 1;
    final user = {
      ...?_users['${item['author_id']}'],
      ...object(item['author']),
    };
    final count = number(item['sub_post_number']);
    final previews = previewReplies(item)
        .where((reply) => !_blocked(reply))
        .toList();
    final openFloor = !_isFloor && (count > 0 || previews.isNotEmpty)
        ? () => _openFloor(item)
        : null;
    final parts = contentParts(item['content']).map((p) => {...p}).toList();
    if (nested && parts.isNotEmpty && number(parts.first['type']) == 0) {
      parts.first['text'] = '${parts.first['text'] ?? ''}'.replaceFirst(
        RegExp(r'^\s*[:：]\s*'),
        '',
      );
    }
    final like = LikeButton(
      key: ValueKey('like-$_viewRevision-${item['id']}'),
      threadId: widget.threadId!,
      postId: isFirstFloor ? '0' : '${item['id']}',
      comment: nested,
      iconOnly: isFirstFloor,
      data: isFirstFloor && _thread['agree'] is Map ? _thread : item,
    );
    return CommentCard(
      key: ValueKey('post-${item['id']}'),
      user: user,
      levelNames: _levelNames,
      nested: nested,
      label: parent ? '原评论' : null,
      fullWidthContent: isFirstFloor,
      isOriginalPoster:
          isFirstFloor ||
          (userKey(user).isNotEmpty &&
              userKey(user) == userKey(object(_thread['author']), _thread)),
      subtitle:
          '${nested ? '' : '${number(item['floor']) > 0
                    ? '${item['floor']}楼'
                    : flag(item['floor_pending'])
                    ? '楼层查询中'
                    : '楼层未知'} · '}${commentTime(item['time'] ?? item['create_time'])}',
      onTap: openFloor,
      onShare: () => _share(item),
      onCopyLink: () => _copyLink(item),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostContent(
            parts: parts,
            videoInfo: {
              if (isFirstFloor) ...object(_thread['video_info']),
              ...object(item['video_info']),
            },
            onTextTap: openFloor,
            textStyle: TextStyle(fontSize: nested ? 15 : 16, height: 1.55),
          ),
          if (!_isFloor &&
              isFirstFloor &&
              object(_thread['poll_info']).isNotEmpty)
            PollCard(
              key: ValueKey(
                'poll-${widget.threadId}-${AuthStore.instance.activeId}',
              ),
              poll: object(_thread['poll_info']),
              hasVoted: _confirmedVotes.contains(AuthStore.instance.activeId),
              onRefresh: _refreshPoll,
              onVote: (options) async {
                final auth = AuthStore.instance;
                if (!auth.isLoggedIn) {
                  await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                  return false;
                }
                final identity = auth.activeId;
                await _api.vote(
                  widget.threadId!,
                  firstText([_forum['id'], _thread['fid']]),
                  options,
                );
                if (!mounted || auth.activeId != identity) return false;
                _confirmedVotes.add(identity);
                return true;
              },
            ),
        ],
      ),
      like: isFirstFloor ? null : like,
      footer: isFirstFloor
          ? ThreadActionBar(
              like: like,
              onReply: _busy || _replyOpening ? null : () => _reply(item),
              onShare: () => _share(),
            )
          : null,
      ip: firstText([user['ip_address'], item['ip_address']]),
      onBlock: userKey(user, item).isEmpty ? null : () => _blockUser(item),
      actions: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _busy || _replyOpening ? null : () => _reply(item),
          icon: const Icon(Icons.reply, size: 16),
          label: const Text('回复'),
        ),
      ),
      preview: openFloor == null
          ? null
          : ReplyPreview(
              replies: previews,
              total: count > previews.length ? count : previews.length,
              users: _users,
              onTap: openFloor,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _items.where((item) => !_blocked(item)).toList();
    return Scaffold(
      bottomNavigationBar: _isForum
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: FilledButton.tonalIcon(
                  onPressed: _busy || _replyOpening || _result == null
                      ? null
                      : () => _reply(),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(_isFloor ? '回复这一楼' : '写回复'),
                ),
              ),
            ),
      appBar: AppBar(
        titleSpacing: 0,
        title: _isForum || _isFloor
            ? Text(_isForum ? '${widget.forum}吧' : '楼中楼')
            : Builder(
                builder: (context) {
                  final name = firstText([
                    _forum['name'],
                    threadForumName(_thread),
                    widget.forum,
                  ]);
                  return TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: name.isEmpty
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReadingPage(forum: name),
                            ),
                          ),
                    icon: ForumAvatar(
                      forum: {..._forum, 'name': name},
                      size: 24,
                    ),
                    label: Text(
                      name.isEmpty ? '加载中' : '$name吧',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
        actions: [
          if (!_isForum)
            IconButton(
              onPressed: () => _share(_isFloor ? _parentPost : null),
              icon: const Icon(Icons.share_outlined),
              tooltip: '分享',
            ),
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
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            _isFloor ? 8 : 12,
            8,
            _isFloor ? 8 : 12,
            16,
          ),
          itemCount: visibleItems.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              if (_isForum) {
                final forum = _forum;
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _busy || _following || _followUncertain
                                ? null
                                : _follow,
                            icon: Icon(_followed ? Icons.check : Icons.add),
                            label: Text(
                              _following
                                  ? '处理中'
                                  : _followUncertain
                                  ? '请刷新核对'
                                  : _followed
                                  ? '已关注'
                                  : '关注',
                            ),
                          ),
                          SignButton(
                            key: ValueKey('sign-$_viewRevision'),
                            name: widget.forum!,
                            followed: _followed,
                            signed:
                                flag(sign['is_sign_in']) ||
                                flag(forum['is_sign_in']),
                          ),
                          ForumLevelBadge(
                            user: {
                              'level_id':
                                  forum['level_id'] ?? forum['user_level'],
                              'is_like': _followed ? 1 : 0,
                            },
                            levelNames: _levelNames,
                          ),
                        ],
                      ),
                      if (_pinned.isNotEmpty)
                        ExpansionTile(
                          key: ValueKey('pinned-${widget.forum}'),
                          title: Text('置顶帖 ${_pinned.length}'),
                          initiallyExpanded: false,
                          children: [
                            for (final pinned in _pinned)
                              ForumThreadCard(
                                thread: pinned,
                                user:
                                    _users['${pinned['author_id']}'] ??
                                    object(pinned['author']),
                                forum: widget.forum!,
                                levelNames: _levelNames,
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
              if (_isFloor) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_parentPost.isNotEmpty)
                      if (!_blocked(_parentPost))
                        _commentCard(_parentPost, parent: true)
                      else
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('原评论作者已被拉黑'),
                        ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Text(
                        '全部回复',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFloor
                          ? (widget.title ?? '楼中楼回复')
                          : '${object(_result?.data['thread'])['title'] ?? widget.title ?? ''}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            }
            if (index == visibleItems.length + 1) {
              return _footer(context);
            }
            final item = visibleItems[index - 1];
            final user = {
              ...?_users['${item['author_id']}'],
              ...object(item['author']),
            };
            if (_isForum) {
              return ForumThreadCard(
                thread: item,
                user: user,
                forum: widget.forum!,
                latestReply: _category == '最新回复',
                levelNames: _levelNames,
              );
            }
            final isFirstFloor = !_isFloor && number(item['floor']) == 1;
            final card = _commentCard(item);
            if (_isForum ||
                _isFloor ||
                !(isFirstFloor ||
                    (index == 1 &&
                        !visibleItems.any((p) => number(p['floor']) == 1)))) {
              return card;
            }
            return Column(
              children: [
                card,
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<bool>(
                    key: _sortAnchor,
                    enabled: !_busy,
                    initialValue: _hot,
                    onSelected: _changeSort,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('按热度排序')),
                      PopupMenuItem(value: false, child: Text('按楼层排序')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_hot ? '按热度排序' : '按楼层排序'),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

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
    if (_items.isEmpty && !_hasMore) {
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
