import '../widgets/app_snack_bar.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/share_content.dart';
import '../widgets/comment_card.dart';
import '../widgets/current_ip_label.dart';
import '../widgets/post_widgets.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/like_button.dart';
import '../widgets/forum_thread_card.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_action_bar.dart';
import 'reply_page.dart';
import 'login_page.dart';
import 'user_page.dart';
import 'post_report_page.dart';

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
    this.targetPostId,
    this.targetReplyId,
  });
  final String? forum, threadId, title, postId;
  final String? targetPostId, targetReplyId;
  final Json? parentPost;
  final TiebaApi? api;
  final Map<int, String> levelNames;
  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> with WidgetsBindingObserver {
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
  late final ScrollController _scroll;
  late String _pageAccount;
  Json _memberInfo = {};
  int? _restorePage;
  int _page = 0;
  bool _busy = false, _onlyAuthor = false, _hasMore = true;
  bool _replyOpening = false;
  bool _hot = false, _following = false, _followUncertain = false;
  bool _descending = false;
  String? _error;
  String _category = '最新回复';
  int _revision = 0;
  int _viewRevision = 0;
  bool _retryReset = true, _savingThread = false, _saveUncertain = false;
  bool? _savedOverride;
  List<Json> _moderators = [];
  String? _moderatorError;
  final _rowKeys = <String, GlobalKey>{};
  final _listKey = GlobalKey();
  Timer? _positionTimer;
  String? _pendingPost, _pendingReply;
  double _restoreDelta = 0;
  bool _restoring = false;
  TiebaPage? _jumpResult;
  int _firstPage = 1;
  bool get _initialLoading => _busy && _items.isEmpty;
  bool get _saved =>
      _savedOverride ??
      flag(_thread['is_store'] ?? object(_thread['store_info'])['is_store']);

  Json _forumUser(Json user) {
    final id = firstText([user['id'], user['user_id']]);
    final moderator = _moderators
        .where((m) => '$id' == '${m['id']}')
        .firstOrNull;
    return moderator == null
        ? user
        : {...user, 'forum_role': moderator['forum_role'], 'is_bawu': 1};
  }

  void _rememberPosition() {
    if (_isForum || _restoring || _items.isEmpty || !_scroll.hasClients) return;
    final viewport = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    String? id;
    double best = double.infinity, delta = 0;
    for (final item in _items) {
      final pid = '${item['id']}';
      final row =
          _rowKeys[pid]?.currentContext?.findRenderObject() as RenderBox?;
      if (row == null || !row.attached || !row.hasSize) continue;
      final y = row.localToGlobal(Offset.zero).dy - top;
      if (y + row.size.height <= 0 || y >= viewport.size.height) continue;
      if (y < best) {
        best = y;
        id = pid;
        delta = -y;
      }
    }
    _rememberPage();
    if (id == null) return;
    final item = _items.firstWhere((p) => '${p['id']}' == id);
    unawaited(
      LocalStore.instance
          .saveReadingPosition(widget.threadId!, {
            'post': id,
            'floor': number(item['floor']),
            'delta': delta,
            'hot': _hot,
            'descending': _descending,
            'only_author': _onlyAuthor,
            'page': number(item['_reading_page']),
          }, parent: widget.postId ?? '')
          .catchError((_) {}),
    );
  }

  void _rememberPage() {
    if (_isForum || _restoring || _result == null || !_scroll.hasClients)
      return;
    LocalStore.instance.rememberReadingPage(_pageAccount, widget.threadId!, {
      'items': List<Json>.of(_items),
      'users': Map<String, Json>.of(_users),
      'thread': Map<String, dynamic>.of(_thread),
      'forum': Map<String, dynamic>.of(_forum),
      'parent': Map<String, dynamic>.of(_parentPost),
      'data': _result!.data,
      'levels': Map<int, String>.of(_levelNames),
      'moderators': List<Json>.of(_moderators),
      'page': _page,
      'first_page': _firstPage,
      'more': _hasMore,
      'hot': _hot,
      'descending': _descending,
      'only_author': _onlyAuthor,
      'offset': _scroll.offset,
      'saved': _savedOverride,
      'save_uncertain': _saveUncertain,
    }, parent: widget.postId ?? '');
  }

  bool _restoreRecentPage() {
    if (_isForum || widget.targetPostId != null || widget.targetReplyId != null)
      return false;
    final page = LocalStore.instance.readingPage(
      _pageAccount,
      widget.threadId!,
      parent: widget.postId ?? '',
    );
    if (page == null) return false;
    _items = objects(page['items']);
    _users = object(page['users'])
        .map((key, value) => MapEntry(key, object(value)));
    _thread = object(page['thread']);
    _forum = object(page['forum']);
    _parentPost = object(page['parent']);
    _result = TiebaPage(object(page['data']));
    _levelNames = Map<int, String>.from(page['levels'] as Map);
    _moderators = objects(page['moderators']);
    _page = number(page['page']);
    _firstPage = number(page['first_page']);
    _hasMore = flag(page['more']);
    _hot = flag(page['hot']);
    _descending = !_hot && flag(page['descending']);
    _onlyAuthor = flag(page['only_author']);
    _savedOverride = page['saved'] as bool?;
    _saveUncertain = flag(page['save_uncertain']);
    _scroll = ScrollController(
      initialScrollOffset: (page['offset'] as num).toDouble(),
    );
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoring = false;
      _rememberPosition();
    });
    return true;
  }

  Json get _myForumLevel {
    final current = object(_result?.data['user']);
    final levelInfo = object(_memberInfo['user_info']);
    final level =
        [
          _forum['level_id'],
          _forum['user_level'],
          current['level_id'],
          current['user_level'],
          levelInfo['level_id'],
          levelInfo['user_level'],
          _memberInfo['level_id'],
        ].map(number).where((n) => n > 0).firstOrNull ??
        0;
    return {
      'level_id': level,
      'level_name': firstText([
        _forum['level_name'],
        current['level_name'],
        levelInfo['level_name'],
        _levelNames[level],
      ]),
    };
  }

  Future<void> _positionAt(String id, {double delta = 0}) async {
    _restoring = true;
    final revision = _revision;
    try {
      for (var attempt = 0; attempt < 35; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || revision != _revision || !_scroll.hasClients) return;
        final target = _rowKeys[id]?.currentContext;
        if (target != null) {
          await Scrollable.ensureVisible(target, alignment: 0);
          if (mounted && _scroll.hasClients && delta != 0) {
            _scroll.jumpTo(
              (_scroll.offset + delta).clamp(
                0.0,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
          return;
        }
        if (_scroll.offset >= _scroll.position.maxScrollExtent) return;
        _scroll.jumpTo(
          (_scroll.offset + _scroll.position.viewportDimension * .8).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      }
    } finally {
      _restoring = false;
    }
  }

  Future<void> _saveThread() async {
    if (_savingThread || _saveUncertain) return;
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
      return;
    }
    final account = AuthStore.instance.activeId, wasSaved = _saved;
    setState(() => _savingThread = true);
    try {
      final pid =
          _items
              .where((p) => number(p['floor']) == 1)
              .map((p) => '${p['id']}')
              .firstOrNull ??
          '0';
      await _api.saveThread(widget.threadId!, pid, remove: wasSaved);
      if (mounted && account == AuthStore.instance.activeId)
        setState(() => _savedOverride = !wasSaved);
    } catch (e) {
      if (mounted && account == AuthStore.instance.activeId) {
        setState(() => _saveUncertain = e is TiebaException && e.uncertain);
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              _saveUncertain
                  ? '收藏结果未确认，请刷新核对'
                  : e is TiebaException
                  ? e.message
                  : '收藏操作失败，请重试',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingThread = false);
    }
  }

  Future<void> _loadDetails(int revision) async {
    final fid = firstText([_forum['id']]);
    if (fid.isEmpty) return;
    await Future.wait([
      () async {
        try {
          final levels = await _api.forumLevels(fid);
          if (mounted && revision == _revision)
            setState(() {
              _memberInfo = levels;
              _levelNames = {
                for (final level in objects(levels['level_info']))
                  number(level['id']): firstText([level['name']]),
              };
            });
        } catch (_) {}
      }(),
      () async {
        try {
          final moderators = await _api.forumModerators(fid);
          if (mounted && revision == _revision)
            setState(() {
              _moderators = moderators;
              _moderatorError = null;
            });
        } catch (_) {
          if (mounted && revision == _revision)
            setState(() => _moderatorError = '吧务信息暂未加载，点击重试');
        }
      }(),
    ]);
  }

  Future<void> _jumpFloor() async {
    final text = TextEditingController();
    final floor = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('跳转楼层'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入楼层号'),
          onSubmitted: (_) {
            final n = int.tryParse(text.text);
            if (n != null && n > 0) Navigator.pop(dialog, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(text.text);
              if (n != null && n > 0) Navigator.pop(dialog, n);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    // The dialog finishes its closing animation before disposing its field.
    Future<void>.delayed(const Duration(milliseconds: 300), text.dispose);
    if (!mounted || floor == null) return;
    final revision = ++_revision;
    setState(() => _busy = true);
    try {
      final result = await _api.threadAtFloor(widget.threadId!, floor);
      if (!mounted || revision != _revision) return;
      final target =
          result.posts.where((p) => number(p['floor']) >= floor).firstOrNull ??
          result.posts.lastOrNull;
      _jumpResult = result;
      _pendingPost = target == null ? null : '${target['id']}';
      _restoreDelta = 0;
      _hot = false;
      _descending = false;
      _onlyAuthor = false;
      await _load(reset: true);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(e is TiebaException ? e.message : '暂时无法跳转，请重试'),
          ),
        );
      }
    }
  }

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
  int get _replySort => _hot
      ? 2
      : _descending
      ? 1
      : 0;
  String get _replySortLabel => _hot
      ? '按热度排序'
      : _descending
      ? '倒序'
      : '正序';

  Future<void> _changeReplies({int? sort, bool? onlyAuthor}) async {
    if (_busy ||
        (sort == null || sort == _replySort) &&
            (onlyAuthor == null || onlyAuthor == _onlyAuthor))
      return;
    final anchor = _sortAnchor.currentContext?.findRenderObject() as RenderBox?;
    final before = anchor?.localToGlobal(Offset.zero).dy;
    final offset = _scroll.hasClients ? _scroll.offset : null;
    _pendingPost = null;
    _pendingReply = null;
    _jumpResult = null;
    _restoreDelta = 0;
    setState(() {
      if (sort != null) {
        _hot = sort == 2;
        _descending = sort == 1;
      }
      if (onlyAuthor != null) _onlyAuthor = onlyAuthor;
    });
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

  Future<void> _backToFirstFloor() async {
    if (_busy) return;
    _positionTimer?.cancel();
    _pendingPost = null;
    _pendingReply = null;
    _jumpResult = null;
    _restoreDelta = 0;
    setState(() {
      _hot = false;
      _descending = false;
      _onlyAuthor = false;
    });
    _restoring = true;
    try {
      await _load(reset: true, pageOverride: 1);
      final revision = _revision;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          revision != _revision ||
          _error != null ||
          !_scroll.hasClients)
        return;
      _scroll.jumpTo(0);
    } finally {
      _restoring = false;
    }
    _rememberPosition();
  }

  bool get _followed =>
      AuthStore.instance.isLoggedIn &&
      (flag(_forum['is_like']) || flag(_forum['is_liked']));

  void _loadNearEnd() {
    _positionTimer?.cancel();
    _positionTimer = Timer(
      const Duration(milliseconds: 650),
      _rememberPosition,
    );
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_busy &&
        _hasMore &&
        _error == null) {
      if (_restoring) return;
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
    if (_replyOpening || _initialLoading) return;
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
                      ? widget.title ?? '写回复'
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
    WidgetsBinding.instance.addObserver(this);
    _api = widget.api ?? TiebaApi();
    _parentPost = {...?widget.parentPost};
    _levelNames = {...widget.levelNames};
    AuthStore.instance.addListener(_accountChanged);
    LocalStore.instance.addListener(_preferencesChanged);
    _pageAccount = AuthStore.instance.activeId;
    final restored = _restoreRecentPage();
    if (!restored) _scroll = ScrollController();
    _scroll.addListener(_loadNearEnd);
    if (restored) {
      LocalStore.instance
          .visitThread(
            widget.threadId!,
            firstText([_thread['title'], widget.title]),
            firstText([_forum['name'], widget.forum]),
          )
          .catchError((_) {});
      return;
    }
    if (_isForum) {
      LocalStore.instance.visit(widget.forum!).catchError((_) {});
    }
    final position = widget.threadId == null
        ? <String, dynamic>{}
        : LocalStore.instance.readingPosition(
            widget.threadId!,
            parent: widget.postId ?? '',
          );
    _pendingPost =
        widget.targetPostId ??
        (!_isFloor ? firstText([position['post']]) : null);
    _pendingReply =
        widget.targetReplyId ??
        (_isFloor ? firstText([position['post']]) : null);
    if (_pendingPost?.isEmpty == true) _pendingPost = null;
    if (_pendingReply?.isEmpty == true) _pendingReply = null;
    if (widget.targetPostId == null && widget.targetReplyId == null) {
      _restoreDelta = (position['delta'] as num?)?.toDouble() ?? 0;
      _onlyAuthor = flag(position['only_author']);
      _hot = !_isFloor && flag(position['hot']);
      _descending = !_isFloor && !_hot && flag(position['descending']);
      if ((_hot || _descending) && number(position['page']) > 0)
        _restorePage = number(position['page']);
    }
    _load(reset: true, pageOverride: _restorePage);
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  bool _blocked(Json item) => LocalStore.instance.userBlocked({
    ...?_users['${item['author_id']}'],
    ...object(item['author']),
  }, item);

  void _accountChanged() {
    LocalStore.instance.clearReadingPages();
    _pageAccount = AuthStore.instance.activeId;
    _memberInfo = {};
    setState(() {
      _items = [];
      _pinned = [];
      _users = {};
      _result = null;
      _thread = {};
      _forum = {};
      _levelNames = {};
      _followUncertain = false;
      _savedOverride = null;
      _saveUncertain = false;
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AuthStore.instance.removeListener(_accountChanged);
    LocalStore.instance.removeListener(_preferencesChanged);
    _api.close();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _rememberPosition();
  }

  Future<void> _load({
    bool reset = false,
    bool preserveFirst = false,
    int? pageOverride,
  }) async {
    if (_busy && !reset) {
      return;
    }
    final revision = ++_revision;
    _retryReset = reset;
    setState(() {
      _busy = true;
      _error = null;
    });
    final next = pageOverride ?? (reset ? 1 : _page + 1);
    final targetPost = reset ? _pendingPost : null;
    final targetReply = reset ? _pendingReply : null;
    final previousFirst = preserveFirst
        ? _items.where((p) => number(p['floor']) == 1).toList()
        : <Json>[];
    try {
      final result =
          _jumpResult ??
          (_isForum
              ? await _api.forum(widget.forum!, next, category: _category)
              : _isFloor
              ? await _api.floor(
                  widget.threadId!,
                  widget.postId!,
                  next,
                  targetReply: targetReply,
                )
              : await _api.thread(
                  widget.threadId!,
                  next,
                  onlyAuthor: _onlyAuthor,
                  hot: _hot,
                  descending: _descending,
                  targetPost: targetPost,
                  onFloorNumbers: (floors) {
                    if (!mounted || !_hot || revision != _revision) return;
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
                ));
      _jumpResult = null;
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
        if (reset) {
          _followUncertain = false;
          _saveUncertain = false;
          _savedOverride = null;
        }
        final actualPage = number(
          object(result.data['page'])['current_page'] ??
              object(result.data['page'])['cur_page'],
        );
        _page = actualPage > 0 ? actualPage : next;
        if (reset) _firstPage = _page;
        _hasMore = result.hasMore;
        var incoming = _isForum
            ? result.threads
            : _isFloor
            ? result.replies
            : result.posts;
        if (!_isForum)
          incoming = incoming
              .map((p) => {...p, '_reading_page': _page})
              .toList();
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
      if (targetPost != null || targetReply != null) {
        _pendingPost = null;
        _pendingReply = null;
        final target = targetReply ?? targetPost!;
        if (_items.any((p) => '${p['id']}' == target)) {
          unawaited(_positionAt(target, delta: _restoreDelta));
        }
        _restoreDelta = 0;
      }
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
      if (reset && !preserveFirst) unawaited(_loadDetails(revision));
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
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('无法打开分享，请稍后重试')));
      }
    }
  }

  Future<void> _report(
    Json item, {
    required bool nested,
    required bool firstFloor,
  }) async {
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted || !AuthStore.instance.isLoggedIn) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PostReportPage(
          threadId: widget.threadId!,
          postId: nested ? widget.postId! : '${item['id']}',
          commentId: nested ? '${item['id']}' : '0',
          title: firstFloor ? '举报帖子' : '举报评论',
        ),
      ),
    );
  }

  Future<void> _blockUser(Json item) async {
    final user = _forumUser({
      ...?_users['${item['author_id']}'],
      ...object(item['author']),
    });
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
    final user = _forumUser({
      ...?_users['${item['author_id']}'],
      ...object(item['author']),
    });
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
      parentPostId: nested ? widget.postId : null,
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
      onReport: () => _report(item, nested: nested, firstFloor: isFirstFloor),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostContent(
            parts: parts,
            highlightReplyTarget: nested,
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
              onReply: _initialLoading || _replyOpening
                  ? null
                  : () => _reply(item),
              onShare: () => _share(),
            )
          : null,
      ip: postIp(item, user),
      ipWidget: nested && postIp(item, user).isEmpty
          ? CurrentIpLabel(
              key: ValueKey('ip-${userKey(user)}-$_pageAccount-$_viewRevision'),
              user: user,
            )
          : null,
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
          onPressed: _initialLoading || _replyOpening
              ? null
              : () => _reply(item),
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
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _rememberPosition();
      },
      child: Scaffold(
        bottomNavigationBar: _isForum
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _initialLoading || _replyOpening || _result == null
                        ? null
                        : () => _reply(),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('写回复'),
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
            if (_isForum && _followed)
              PopupMenuButton<String>(
                onSelected: (_) => _follow(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'unfollow',
                    enabled: !_busy && !_following && !_followUncertain,
                    child: const Text('取消关注'),
                  ),
                ],
              ),
            if (!_isForum && !_isFloor)
              IconButton(
                onPressed: _savingThread || _saveUncertain || _thread.isEmpty
                    ? null
                    : _saveThread,
                icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_outline),
                tooltip: _saved ? '取消收藏' : '收藏',
              ),
            if (_isFloor)
              IconButton(
                onPressed: () => _share(_isFloor ? _parentPost : null),
                icon: const Icon(Icons.share_outlined),
                tooltip: '分享',
              ),
            if (!_isForum && !_isFloor)
              PopupMenuButton<String>(
                icon: const Icon(Icons.swap_vert),
                tooltip: '楼层跳转',
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'jump') {
                    _jumpFloor();
                    return;
                  }
                  if (value == 'share') {
                    _share();
                    return;
                  }
                  if (value == 'top') {
                    _backToFirstFloor();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'jump', child: Text('跳转楼层')),
                  const PopupMenuItem(value: 'top', child: Text('回到一楼')),
                  const PopupMenuItem(value: 'share', child: Text('分享帖子')),
                ],
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
            key: _listKey,
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              _isForum ? 12 : 6,
              8,
              _isForum ? 12 : 6,
              16,
            ),
            itemCount: visibleItems.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (_isForum) {
                  final forum = _forum;
                  final sign = object(
                    object(forum['sign_in_info'])['user_info'],
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ForumAvatar(forum: forum, size: 56),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.forum}吧',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  if (AuthStore.instance.isLoggedIn &&
                                      number(_myForumLevel['level_id']) > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 3,
                                      ),
                                      child: ForumLevelBadge(
                                        user: _myForumLevel,
                                        levelNames: _levelNames,
                                      ),
                                    ),
                                  Text(
                                    '关注 ${forum['member_num'] ?? 0} · 帖子 ${forum['thread_num'] ?? 0}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_followed)
                              SignButton(
                                key: ValueKey('sign-$_viewRevision'),
                                name: widget.forum!,
                                followed: true,
                                compact: true,
                                signed:
                                    flag(sign['is_sign_in']) ||
                                    flag(forum['is_sign_in']),
                              )
                            else
                              FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  minimumSize: const Size(72, 36),
                                ),
                                onPressed:
                                    _busy || _following || _followUncertain
                                    ? null
                                    : _follow,
                                child: Text(
                                  _following
                                      ? '关注中'
                                      : _followUncertain
                                      ? '请刷新'
                                      : '关注',
                                ),
                              ),
                          ],
                        ),
                        ExpansionTile(
                          title: Text(
                            '吧务团队${_moderators.isEmpty ? '' : ' · ${_moderators.length}'}',
                          ),
                          children: [
                            if (_moderatorError != null)
                              TextButton(
                                onPressed: () => _loadDetails(_revision),
                                child: Text(_moderatorError!),
                              ),
                            for (final member in _moderators)
                              ListTile(
                                leading: UserAvatar(user: member),
                                title: Text(author(member)),
                                trailing: ForumRoleBadge(user: member),
                                onTap: () => openUser(context, member),
                              ),
                            if (_moderators.isEmpty && _moderatorError == null)
                              const ListTile(title: Text('暂无吧务名单')),
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
                                  user: _forumUser(
                                    _users['${pinned['author_id']}'] ??
                                        object(pinned['author']),
                                  ),
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
                                        if (!selected ||
                                            _category == category) {
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
                      if (_firstPage > 1)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _load(
                                  reset: true,
                                  pageOverride: _firstPage - 1,
                                ),
                          child: const Text('查看前面的回复'),
                        ),
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
                      if (_firstPage > 1)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _load(
                                  reset: true,
                                  pageOverride: _firstPage - 1,
                                ),
                          child: const Text('查看前面的楼层'),
                        ),
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
                  user: _forumUser(user),
                  forum: widget.forum!,
                  latestReply: _category == '最新回复',
                  levelNames: _levelNames,
                );
              }
              final isFirstFloor = !_isFloor && number(item['floor']) == 1;
              final card = KeyedSubtree(
                key: _rowKeys.putIfAbsent('${item['id']}', () => GlobalKey()),
                child: _commentCard(item),
              );
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
                  Row(
                    key: _sortAnchor,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('全部回复')),
                              ButtonSegment(value: true, label: Text('只看楼主')),
                            ],
                            selected: {_onlyAuthor},
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              textStyle: const TextStyle(fontSize: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onSelectionChanged: _busy
                                ? null
                                : (value) =>
                                      _changeReplies(onlyAuthor: value.single),
                          ),
                        ),
                      ),
                      PopupMenuButton<int>(
                        enabled: !_busy,
                        initialValue: _replySort,
                        onSelected: (sort) => _changeReplies(sort: sort),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 2, child: Text('按热度排序')),
                          PopupMenuItem(value: 0, child: Text('正序')),
                          PopupMenuItem(value: 1, child: Text('倒序')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _replySortLabel,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const Icon(Icons.expand_more, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
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
              onPressed: () => _load(reset: _retryReset),
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
