import '../widgets/app_snack_bar.dart';
import '../widgets/bow_share_button.dart';
import '../widgets/shatter_effect.dart';
import '../widgets/building_content.dart';
import '../widgets/scroll_away_header.dart';
import '../widgets/feed_icons.dart';

import 'dart:async';
import 'dart:io';

import '../features/reading/reading_controller.dart';
import '../features/reading/reading_viewport.dart';
import '../features/reading/reading_entry.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../data/tieba_api.dart';
import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/share_content.dart';
import '../widgets/comment_card.dart';
import '../widgets/current_ip_label.dart';
import '../widgets/post_widgets.dart';
import '../widgets/forum_widgets.dart';
import '../widgets/forum_feed_pager.dart';
import '../widgets/forum_header_card.dart';
import '../widgets/like_button.dart';
import '../widgets/forum_thread_card.dart';
import '../widgets/thread_thumbnails.dart';
import '../widgets/poll_card.dart';
import '../widgets/post_action_bar.dart';
import 'reply_page.dart';
import 'login_page.dart';
import 'post_report_page.dart';
import 'forum_details_page.dart';
import 'forum_search_page.dart';
import 'forum_poster_page.dart';

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
    this.initialPage,
    this.previewThread,
  });
  final String? forum, threadId, title, postId;
  final String? targetPostId, targetReplyId;
  final Json? parentPost;
  final TiebaApi? api;
  final TiebaPage? initialPage;
  final Json? previewThread;
  final Map<int, String> levelNames;
  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> with WidgetsBindingObserver {
  late final TiebaApi _api;
  late final ReadingController _reader;
  TiebaPage? get _result => _reader.data.result;
  List<Json> get _items => _reader.data.items;
  List<Json> get _pinned => _reader.data.pinned;
  final _sortAnchor = GlobalKey();
  final _forumIdentityKey = GlobalKey();
  final _forumTabsScroll = ScrollController();
  final _forumTabsKey = GlobalKey();
  final _forumCategoryKeys = <String, GlobalKey>{};
  static const _forumCategories = ['精华', '热门', '最新回复', '最新发布'];
  ForumSection? _section;
  bool _forumHeaderCollapsed = false;

  void _updateForumHeader() {
    if (!_isForum || !_scroll.hasClients) return;
    final identity =
        _forumIdentityKey.currentContext?.findRenderObject() as RenderBox?;
    if (identity == null || !identity.hasSize) return;
    final collapsed = _scroll.offset >= identity.size.height + 16;
    if (collapsed != _forumHeaderCollapsed) {
      setState(() => _forumHeaderCollapsed = collapsed);
    }
  }

  Map<String, Json> get _users => _reader.data.users;
  Json get _thread => _reader.data.thread;
  Json get _forum => _reader.data.forum;
  Json get _parentPost => _reader.data.parent;
  Json? _previewThread;
  final _confirmedVotes = <String>{};
  Map<int, String> _levelNames = {};
  late final ScrollController _scroll;
  late String _pageAccount;
  Json _memberInfo = {};
  int get _page => _reader.data.page;
  bool _onlyAuthor = false;
  bool get _busy => _reader.busy;
  bool get _hasMore => _reader.data.hasMore;
  bool _replyOpening = false;
  bool _floorOpening = false;
  bool _toolbarHidden = false;
  final _toolbarOffset = ValueNotifier<double>(0);
  double? _lastToolbarPixels;
  late bool _mode = LocalStore.instance.buildingMode;
  bool get _building => _mode && !_isForum && !_isFloor;
  final _removing = <String>{};
  double _toolbarDrag = 0;

  void _followToolbarScroll() {
    final position = _scroll.position;
    final pixels = position.pixels.clamp(0.0, position.maxScrollExtent);
    final previous = _lastToolbarPixels ?? _scroll.initialScrollOffset;
    _lastToolbarPixels = pixels;
    if (_isForum || _building || _restoring) return;
    // Follow the scroll position before layout, including fling motion. Keep
    // updates local to the overlay instead of rebuilding the post list.
    if (pixels <= 0) {
      _toolbarOffset.value = 0;
    } else if (position.isScrollingNotifier.value) {
      _toolbarOffset.value = (_toolbarOffset.value + pixels - previous).clamp(
        0.0,
        48.0,
      );
    }
  }

  bool _trackToolbar(ScrollNotification notification) {
    if (_building &&
        notification.depth == 0 &&
        notification is OverscrollNotification &&
        notification.overscroll < 0) {
      _loadNearEnd();
    }
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _viewport.cancel();
    }
    if (_isForum || notification.depth != 0 || _restoring) return false;
    if (_building) {
      if (notification is ScrollStartNotification) _toolbarDrag = 0;
      if (notification is ScrollUpdateNotification &&
          notification.dragDetails != null) {
        final delta = notification.scrollDelta ?? 0;
        if (_toolbarDrag.sign != delta.sign) _toolbarDrag = 0;
        _toolbarDrag += delta;
        if (_toolbarDrag.abs() >= 12) {
          final hidden = delta > 0;
          if (_toolbarHidden != hidden) setState(() => _toolbarHidden = hidden);
        }
      }
      return false;
    }
    return false;
  }

  bool _hot = false;
  bool _descending = false;
  String? get _error => _reader.error;
  String _category = '热门';
  int get _revision => _reader.revision;
  int _viewRevision = 0;
  Future<void> Function()? _retryLoad;
  bool _savingThread = false, _saveUncertain = false;
  bool _sharingForum = false;
  bool? _savedOverride;
  List<Json> _moderators = [];
  final _viewport = ReadingViewport();
  Map<String, GlobalKey> get _rowKeys => _viewport.rows;
  final _shatterKeys = <String, GlobalKey>{};
  final _blocking = <String>{};
  GlobalKey get _listKey => _viewport.key;
  Timer? _positionTimer;
  Timer? _highlightTimer;
  String? _highlightedReply;
  bool get _restoring => _viewport.restoring;
  int get _firstPage => _reader.data.firstPage;
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
    final anchor = _viewport.visibleAnchor(
      topInset: _building ? 0 : 48 - _toolbarOffset.value,
    );
    final id = anchor?.id;
    final delta = anchor?.delta ?? 0;
    _rememberPage();
    if (id == null || !_items.any((post) => '${post['id']}' == id)) return;
    final item = _items.firstWhere((p) => '${p['id']}' == id);
    unawaited(
      LocalStore.instance
          .saveReadingPosition(widget.threadId!, {
            'post': id,
            'floor': number(item['floor']),
            'delta': delta,
            'building': _building,
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
    // The store rejects longer pages; avoid copying them just to discard them.
    if (_items.length > 240) {
      LocalStore.instance.rememberReadingPage(_pageAccount, widget.threadId!, {
        'items': _items,
      }, parent: widget.postId ?? '');
      return;
    }
    LocalStore.instance.rememberReadingPage(_pageAccount, widget.threadId!, {
      ..._reader.data.toCache(),
      'levels': Map<int, String>.of(_levelNames),
      'moderators': List<Json>.of(_moderators),
      'hot': _hot,
      'descending': _descending,
      'only_author': _onlyAuthor,
      'offset': _scroll.offset,
      'building': _building,
      'saved': _savedOverride,
      'save_uncertain': _saveUncertain,
    }, parent: widget.postId ?? '');
  }

  Future<void> _restoreRecentPage(Json page) async {
    _reader.restore(page);
    _levelNames = Map<int, String>.from(page['levels'] as Map);
    _moderators = objects(page['moderators']);
    _savedOverride = page['saved'] as bool?;
    _saveUncertain = flag(page['save_uncertain']);
    final placement = _viewport.begin(hideContent: true);
    final revision = _revision;
    try {
      await _viewport.placeOffset(
        token: placement,
        scroll: _scroll,
        valid: () => mounted && _reader.accepts(revision),
        offset: () => (page['offset'] as num?)?.toDouble() ?? 0,
      );
    } finally {
      _viewport.finish(placement);
    }
    if (mounted) _rememberPosition();
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

  Future<void> _positionAt(int placement, ReadingEntry entry) async {
    final id = entry.target!;
    final dataRevision = _revision;
    final result = await _viewport.locate(
      token: placement,
      scroll: _scroll,
      id: id,
      delta: entry.delta,
      valid: () => mounted && _reader.accepts(dataRevision),
      building: _building,
      nested: _isFloor,
      topInset: _building ? 0 : 48 - _toolbarOffset.value,
      firstFloor: _items.any(
        (post) => '${post['id']}' == id && number(post['floor']) == 1,
      ),
    );
    if (!mounted || !_viewport.isCurrent(placement)) return;
    setState(() {
      if (result == PlacementResult.located &&
          _isFloor &&
          id == widget.targetReplyId) {
        _highlightedReply = id;
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _highlightedReply = null);
        });
      }
    });
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
            });
        } catch (_) {}
      }(),
    ]);
  }

  Future<void> _jumpFloor() async {
    var text = '';
    final floor = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('跳转楼层'),
        content: TextField(
          onChanged: (value) => text = value,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入楼层号'),
          onSubmitted: (_) {
            final n = int.tryParse(text);
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
              final n = int.tryParse(text);
              if (n != null && n > 0) Navigator.pop(dialog, n);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (!mounted || floor == null) return;
    final revision = _reader.beginExternalLoad();
    final placement = _viewport.begin();

    try {
      final result = await _api.threadAtFloor(widget.threadId!, floor);
      if (!mounted || revision != _revision) return;
      if (!_viewport.isCurrent(placement)) return;
      final target =
          result.posts.where((p) => number(p['floor']) >= floor).firstOrNull ??
          result.posts.lastOrNull;
      _hot = false;
      _descending = false;
      _onlyAuthor = false;
      await _load(
        reset: true,
        placement: placement,
        entry: ReadingEntry(post: target == null ? null : '${target['id']}'),
        initialPage: result,
      );
    } catch (e) {
      if (mounted && revision == _revision) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(e is TiebaException ? e.message : '暂时无法跳转，请重试'),
          ),
        );
      }
    } finally {
      _reader.finishExternalLoad(revision);
      _viewport.finish(placement);
    }
  }

  bool get _isForum => widget.threadId == null;
  bool get _isFloor => widget.postId != null;
  Future<void> _openFloor(Json item, {String? replyId}) async {
    if (_floorOpening) return;
    _floorOpening = true;
    try {
      FocusScope.of(context).unfocus();
      // The destination owns loading and retry. A slow request must never
      // hold navigation (and all subsequent taps) on the source page.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReadingPage(
            threadId: widget.threadId,
            postId: '${item['id']}',
            targetReplyId: replyId,
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
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(e is TiebaException ? e.message : '评论加载失败，请稍后重试'),
          ),
        );
    } finally {
      _floorOpening = false;
    }
  }

  int get _replySort => _hot
      ? 2
      : _descending
      ? 1
      : 0;
  String get _replySortLabel => _hot
      ? (_building ? '热门' : '按热度排序')
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
    setState(() {
      if (sort != null) {
        _hot = sort == 2;
        _descending = sort == 1;
      }
      if (onlyAuthor != null) _onlyAuthor = onlyAuthor;
    });
    final placement = _viewport.begin();
    final loading = _load(
      reset: true,
      preserveFirst: true,
      placement: placement,
    );
    final revision = _revision;
    try {
      await loading;
      await _viewport.placeOffset(
        token: placement,
        scroll: _scroll,
        valid: () => mounted && _reader.accepts(revision) && _error == null,
        offset: () {
          final current =
              _sortAnchor.currentContext?.findRenderObject() as RenderBox?;
          final after = current?.localToGlobal(Offset.zero).dy;
          return before != null && after != null
              ? _scroll.offset + (_building ? before - after : after - before)
              : offset;
        },
      );
    } finally {
      _viewport.finish(placement);
    }
  }

  Future<void> _backToFirstFloor() async {
    if (_busy) return;
    _positionTimer?.cancel();
    setState(() {
      _hot = false;
      _descending = false;
      _onlyAuthor = false;
    });
    final placement = _viewport.begin();
    final loading = _load(reset: true, pageOverride: 1, placement: placement);
    final revision = _revision;
    try {
      await loading;
      await _viewport.placeOffset(
        token: placement,
        scroll: _scroll,
        valid: () => mounted && _reader.accepts(revision) && _error == null,
        offset: () => 0,
      );
    } finally {
      _viewport.finish(placement);
    }
    if (mounted) _rememberPosition();
  }

  bool get _followed => AuthStore.instance.isLoggedIn && _reader.forumFollowed;

  void _loadNearEnd() {
    if (_isForum) return;
    _positionTimer?.cancel();
    _positionTimer = Timer(
      const Duration(milliseconds: 650),
      _rememberPosition,
    );
    if (!_scroll.hasClients || _busy || _restoring || _error != null) return;
    if (_building &&
        _firstPage > 1 &&
        _scroll.position.extentBefore < 300 &&
        _scroll.position.userScrollDirection == ScrollDirection.forward) {
      _load(previous: true);
    } else if (_scroll.position.extentAfter < 600 && _hasMore) {
      _load();
    }
  }

  Future<void> _follow(bool followed) async {
    if (_reader.forumActionsBusy || _reader.forumFollowUncertain) return;
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    final account = AuthStore.instance.activeId;
    try {
      final changed = await _reader.changeForumFollowed(
        widget.forum!,
        followed,
      );
      if (!mounted || AuthStore.instance.activeId != account) return;
      if (changed) await _refreshForumInfo();
    } catch (e) {
      if (mounted && AuthStore.instance.activeId == account) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              e is TiebaException
                  ? (e.uncertain ? '关注结果未确认，请刷新核对' : e.message)
                  : '关注操作失败，请重试',
            ),
          ),
        );
        if (e is TiebaException && e.uncertain) {
          await _refreshForumInfo();
        }
      }
    }
  }

  Future<void> _refreshForumInfo() async {
    final account = AuthStore.instance.activeId;
    try {
      await _reader.refreshForum(widget.forum!);
    } catch (error) {
      if (mounted && account == AuthStore.instance.activeId) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              error is TiebaException ? error.message : '吧资料刷新失败，请稍后重试',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showForumShare() async {
    if (_sharingForum) return;
    final content = ShareContent.forForum(widget.forum!, _forum);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '分享${widget.forum}吧',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(Platform.isWindows ? '复制吧简介与链接' : '分享吧链接'),
              onTap: () => Navigator.pop(sheet, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制吧链接'),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('制作分享海报'),
              onTap: () => Navigator.pop(sheet, 'poster'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() => _sharingForum = true);
    try {
      if (action == 'copy') {
        await content.copyLink();
        if (mounted)
          ScaffoldMessenger.of(context)
              .showAppSnackBar(const AppSnackBar(content: Text('吧链接已复制')));
      } else if (action == 'share') {
        await content.shareLink();
        if (mounted && Platform.isWindows) {
          ScaffoldMessenger.of(context).showAppSnackBar(
            const AppSnackBar(content: Text('吧简介与链接已复制')),
          );
        }
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ForumPosterPage(content: content),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('分享失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _sharingForum = false);
    }
  }

  void _openForumDetails() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForumDetailsPage(
          name: widget.forum!,
          reader: _reader,
          onFollow: _follow,
          onRefresh: _refreshForumInfo,
          api: _api,
        ),
      ),
    );
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
      final building = _building;
      final sent = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭评论',
        barrierColor: Colors.black.withValues(alpha: .4),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => ReplyComposerSheet(
          building: building,
          builder: (controller, toggle, expanded, emojiChanged, drag) =>
              ReplyPage(
                building: building,
                scrollController: controller,
                onExpand: toggle,
                expanded: expanded,
                onEmojiChanged: emojiChanged,
                onDrag: drag,
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
                    : firstText([
                        user['id'],
                        user['user_id'],
                        item['author_id'],
                      ]),
              ),
        ),
        transitionBuilder: (context, animation, _, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: Offset(0, building ? -1 : 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
            child: child,
          );
        },
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
    _reader = ReadingController(_api, parent: {...?widget.parentPost});
    _reader.addListener(_readingChanged);
    _highlightedReply = widget.targetReplyId;
    _viewport.addListener(_readingChanged);

    _previewThread = widget.previewThread;
    _levelNames = {...widget.levelNames};
    AuthStore.instance.addListener(_accountChanged);
    LocalStore.instance.addListener(_preferencesChanged);
    _pageAccount = AuthStore.instance.activeId;
    final entry = _isForum
        ? const ReadingEntry()
        : ReadingEntry.resolve(
            building: _building,
            nested: _isFloor,
            targetPost: widget.targetPostId,
            targetReply: widget.targetReplyId,
            cache: LocalStore.instance.readingPage(
              _pageAccount,
              widget.threadId!,
              parent: widget.postId ?? '',
            ),
            position: LocalStore.instance.readingPosition(
              widget.threadId!,
              parent: widget.postId ?? '',
            ),
          );
    _scroll = ScrollController(
      initialScrollOffset: (entry.cache?['offset'] as num?)?.toDouble() ?? 0,
    );
    _scroll.addListener(_loadNearEnd);
    _scroll.addListener(_updateForumHeader);
    _scroll.addListener(_followToolbarScroll);
    _hot = entry.hot;
    _descending = entry.descending;
    _onlyAuthor = entry.onlyAuthor;
    if (entry.cache case final page?) {
      unawaited(_restoreRecentPage(page));
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
    _load(
      reset: true,
      entry: entry,
      pageOverride: entry.page,
      initialPage: widget.initialPage,
    );
  }

  void _preferencesChanged() {
    if (!mounted) return;
    final next = LocalStore.instance.buildingMode;
    if (_mode != next) {
      _viewport.cancel();
      setState(() => _mode = next);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      setState(() {});
    }
  }

  bool _blocked(Json item) =>
      LocalStore.instance.blockedUsers.isNotEmpty &&
      LocalStore.instance.userBlocked({
        ...?_users['${item['author_id']}'],
        ...object(item['author']),
      }, item);

  void _accountChanged() {
    _viewport.cancel();
    _positionTimer?.cancel();
    LocalStore.instance.clearReadingPages();
    _pageAccount = AuthStore.instance.activeId;
    _memberInfo = {};
    _section = null;
    if (_isForum) _category = '热门';
    _reader.clear();
    setState(() {
      _previewThread = null;

      _levelNames = {};
      _savedOverride = null;
      _saveUncertain = false;
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _highlightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AuthStore.instance.removeListener(_accountChanged);
    LocalStore.instance.removeListener(_preferencesChanged);
    _viewport.removeListener(_readingChanged);
    _viewport.cancel();
    _viewport.dispose();
    _reader.removeListener(_readingChanged);
    _reader.dispose();
    _api.close();
    _scroll.dispose();
    _toolbarOffset.dispose();
    _forumTabsScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _rememberPosition();
  }

  void _readingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({
    bool reset = false,
    bool previous = false,
    bool preserveFirst = false,
    int? pageOverride,
    ReadingEntry entry = const ReadingEntry(),
    TiebaPage? initialPage,
    int? placement,
  }) async {
    if (_busy && !reset) return;
    // Retry the same immutable destination, but as a new placement operation.
    _retryLoad = () => _load(
      reset: reset,
      previous: previous,
      preserveFirst: preserveFirst,
      pageOverride: pageOverride,
      entry: entry,
    );
    final ownsPlacement = (reset || previous) && placement == null;
    var token =
        placement ??
        (reset ? _viewport.begin(hideContent: entry.target != null) : null);
    try {
      final loaded = await _reader.load(
        ReadingQuery(
          forum: widget.forum,
          threadId: widget.threadId,
          postId: widget.postId,
          category: _isForum ? '热门' : _category,
          section: _isForum ? null : _section,
          hot: _hot,
          descending: _descending,
          onlyAuthor: _onlyAuthor,
        ),
        reset: reset,
        previous: previous,
        preserveFirst: preserveFirst,
        pageOverride: pageOverride,
        targetPost: reset ? entry.post : null,
        targetReply: reset ? entry.reply : null,
        initialPage: initialPage,
      );
      if (!mounted) return;
      if (loaded == null) return;
      if (!_reader.accepts(loaded.revision)) return;
      final anchor = previous ? _viewport.visibleAnchor() : null;
      if (anchor != null) token = _viewport.begin();
      setState(() {
        if (loaded.unsupportedHot) _hot = false;
        if (reset && !preserveFirst) _viewRevision++;
        if (reset) {
          _saveUncertain = false;
          _savedOverride = null;
        }
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
      if (loaded.unsupportedHot) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          const AppSnackBar(content: Text('该帖暂不支持热度排序，已按楼层显示')),
        );
      }
      if (reset && !preserveFirst) unawaited(_loadDetails(loaded.revision));
      if (anchor != null && token != null) {
        await _viewport.restoreAnchor(
          token: token,
          scroll: _scroll,
          anchor: anchor,
          valid: () => mounted && _reader.accepts(loaded.revision),
          building: _building,
        );
      }
      if (token != null &&
          entry.target != null &&
          _viewport.isCurrent(token) &&
          _items.any((post) => '${post['id']}' == entry.target)) {
        await _positionAt(token, entry);
      }
    } finally {
      // An old completion cannot reveal or release a newer operation.
      if (ownsPlacement && token != null) _viewport.finish(token);
    }
  }

  ShareContent _shareContent([Json? item]) {
    final isComment = item != null && (_isFloor || number(item['floor']) != 1);
    final source =
        item ??
        _items.where((post) => number(post['floor']) == 1).firstOrNull ??
        _thread;
    final data = {
      ...source,
      'author': {
        if (!isComment) ...object(_thread['author']),
        ...?_users['${source['author_id']}'],
        ...object(source['author']),
      },
    };
    return ShareContent.post(
      threadId: widget.threadId!,
      title: firstText([_thread['title'], widget.title]),
      forum: firstText([_forum['name'], widget.forum]),
      postId: isComment ? (_isFloor ? widget.postId! : '${source['id']}') : '',
      comment: isComment ? data : null,
      post: isComment ? null : data,
    );
  }

  Future<void> _share([Json? item]) async {
    try {
      var source = item;
      if (source == null &&
          !_isFloor &&
          !_items.any((post) => number(post['floor']) == 1)) {
        final result = await _api.thread(widget.threadId!, 1);
        source = result.posts
            .where((post) => number(post['floor']) == 1)
            .firstOrNull;
      }
      if (!mounted) return;
      await _shareContent(source).share();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showAppSnackBar(const AppSnackBar(content: Text('无法生成分享图片，请稍后重试')));
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
    if (!_blocking.add(key)) return;
    try {
      await shatterRemove(_shatterKeys['${item['id']}'], () async {
        if (_building) {
          setState(() => _removing.add(key));
          await Future<void>.delayed(
            MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 420),
          );
        }
        await LocalStore.instance.blockUser(key, author(user));
      }, bricks: _building);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('拉黑保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _removing.remove(key));
      _blocking.remove(key);
    }
  }

  Future<void> _refreshPoll() async {
    final account = AuthStore.instance.activeId;
    final result = await _api.thread(widget.threadId!, 1);
    if (!mounted || account != AuthStore.instance.activeId) return;
    final poll = object(object(result.data['thread'])['poll_info']);
    if (poll.isEmpty) throw const TiebaException('票数暂时不可用，请稍后刷新');
    _reader.setPoll(poll);
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
    for (final part in parts) {
      if (number(part['type']) != 4 || firstText([part['text']]).isNotEmpty) {
        continue;
      }
      final uid = firstText([part['uid'], part['user_id']]);
      final portrait = firstText([part['portrait']]).split('?').first;
      final candidates = [
        ..._users.values,
        object(_parentPost['author']),
        ..._items.map((post) => object(post['author'])),
      ];
      final target = candidates
          .where(
            (candidate) =>
                (uid.isNotEmpty &&
                    uid != '0' &&
                    firstText([candidate['id'], candidate['user_id']]) ==
                        uid) ||
                (portrait.isNotEmpty &&
                    firstText([candidate['portrait']]).split('?').first ==
                        portrait),
          )
          .firstOrNull;
      if (target != null) {
        part['text'] = firstText([
          target['name_show'],
          target['show_nickname'],
          target['name'],
        ]);
      }
    }
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
      feedColors: true,
      iconSize: 20,
      data: isFirstFloor && _thread['agree'] is Map ? _thread : item,
      onChanged: (source, patch) =>
          _reader.updateLike(source, patch, firstFloor: isFirstFloor),
    );
    return RepaintBoundary(
      key: _shatterKeys.putIfAbsent('${item['id']}', () => GlobalKey()),
      child: CommentCard(
        building: _mode,
        key: ValueKey('post-${item['id']}'),
        user: user,
        levelNames: _levelNames,
        nested: nested,
        highlighted: nested && '${item['id']}' == _highlightedReply,
        label: parent ? '原评论' : null,
        fullWidthContent: isFirstFloor,
        isOriginalPoster:
            isFirstFloor ||
            (userKey(user).isNotEmpty &&
                userKey(user) == userKey(object(_thread['author']), _thread)),
        subtitle: commentTime(item['time'] ?? item['create_time']),
        onTap: openFloor,
        onShare: () => _share({...item, 'content': parts}),
        onReport: () => _report(item, nested: nested, firstFloor: isFirstFloor),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BuildingContent(
              enabled: _building,
              parts: parts,
              child: PostContent(
                parts: parts,
                adaptiveImages: true,
                highlightReplyTarget: nested,
                videoInfo: {
                  if (isFirstFloor) ...object(_thread['video_info']),
                  ...object(item['video_info']),
                },
                onTextTap: openFloor,
                textStyle: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontSize: nested ? 15 : 16, height: 1.5),
              ),
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
        like: null,
        footer: isFirstFloor
            ? ThreadActionBar(
                building: _mode,
                replyCount: number(_thread['reply_num']),
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
                key: ValueKey(
                  'ip-${userKey(user)}-$_pageAccount-$_viewRevision',
                ),
                user: user,
              )
            : null,
        onBlock: userKey(user, item).isEmpty ? null : () => _blockUser(item),
        actions: CommentActionBar(
          building: _mode,
          floor: number(item['floor']) > 0 ? "${item['floor']}楼" : '',
          like: like,
          onReply: _initialLoading || _replyOpening ? null : () => _reply(item),
          onShare: () => _share({...item, 'content': parts}),
        ),
        preview: openFloor == null
            ? null
            : ReplyPreview(
                replies: previews,
                total: count > previews.length ? count : previews.length,
                users: _users,
                onTap: openFloor,
                onReplyTap: (reply) =>
                    _openFloor(item, replyId: '${reply['id']}'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _items.where((item) => !_blocked(item)).toList();
    final toolbar = AppBar(
      backgroundColor: _isForum ? Colors.transparent : null,
      foregroundColor: _isForum ? Colors.white : null,
      surfaceTintColor: _isForum ? Colors.transparent : null,
      elevation: _isForum ? 0 : null,
      primary: false,
      toolbarHeight: _isForum ? 56 : 48,
      titleSpacing: 0,
      title: _isForum
          ? _forumHeaderCollapsed
                ? InkWell(
                    onTap: _openForumDetails,
                    child: Row(
                      children: [
                        ForumAvatar(
                          forum: {..._forum, 'name': widget.forum},
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${widget.forum}吧',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null
          : _isFloor
          ? const Text('楼中楼')
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
                  icon: ForumAvatar(forum: {..._forum, 'name': name}, size: 24),
                  label: Text(
                    name.isEmpty ? '加载中' : '$name吧',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
      actions: [
        if (!_isForum && !_isFloor)
          SizedBox(
            width: 52,
            height: 48,
            child: IconButton(
              onPressed: _savingThread || _saveUncertain || _thread.isEmpty
                  ? null
                  : _saveThread,
              icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_outline),
              tooltip: _saved ? '取消收藏' : '收藏',
            ),
          ),
        if (_isFloor)
          BowShareButton(onShare: () => _share(_isFloor ? _parentPost : null)),
        if (!_isForum && !_isFloor)
          SizedBox(
            width: 52,
            height: 48,
            child: PopupMenuButton<String>(
              icon: const FeedIcon(FeedGlyph.stairs, size: 22),
              tooltip: '楼层跳转',
              enabled: !_busy,
              onSelected: (value) {
                if (value == 'jump') {
                  _jumpFloor();
                  return;
                }
                if (value == 'top') {
                  _backToFirstFloor();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'jump', child: Text('跳转楼层')),
                const PopupMenuItem(value: 'top', child: Text('回到一楼')),
              ],
            ),
          ),
        if (!_isForum && !_isFloor) const SizedBox(width: 12),
        if (_isForum)
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ForumSearchPage(
                  name: widget.forum!,
                  levelNames: _levelNames,
                ),
              ),
            ),
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            tooltip: '吧内搜索',
          ),
        if (_isForum)
          IgnorePointer(
            ignoring: _sharingForum,
            child: BowShareButton(
              onShare: _showForumShare,
              color: Colors.white,
              tooltip: '分享吧',
            ),
          ),
        if (_isForum) const SizedBox(width: 8),
      ],
    );
    final replyBar = Padding(
      padding: _building
          ? const EdgeInsets.fromLTRB(16, 2, 16, 2)
          : const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: FilledButton.tonalIcon(
        style: _building
            ? FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13),
              )
            : FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                textStyle: Theme.of(context).textTheme.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
        onPressed: _initialLoading || _replyOpening || _result == null
            ? null
            : () => _reply(),
        icon: _building
            ? const FeedIcon(FeedGlyph.brick, size: 18)
            : const Icon(Icons.edit_outlined, size: 18),
        label: Text(_building ? '盖楼' : '写回复'),
      ),
    );
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _rememberPosition();
      },
      child: Scaffold(
        bottomNavigationBar: _isForum
            ? null
            : _building
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: _toolbarHidden ? 0 : 1),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                child: SafeArea(
                  top: false,
                  child: SizedBox(height: 48, child: toolbar),
                ),
                builder: (_, value, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: value,
                    child: IgnorePointer(
                      ignoring: _toolbarHidden,
                      child: child,
                    ),
                  ),
                ),
              )
            : SafeArea(top: false, child: replyBar),
        body: _forumBackground(
          _readingLayout(
            header: ValueListenableBuilder<double>(
              valueListenable: _toolbarOffset,
              child: _building ? replyBar : toolbar,
              builder: (_, offset, child) => ScrollAwayHeader(
                offset: !_isForum && !_building ? offset : 0,
                height: _building ? 36 : (_isForum ? 56 : 48),
                child: child!,
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: _trackToolbar,
              child: RefreshIndicator(
                // In the reversed building list, pulling down at the paging
                // edge must not reset the floors that have already loaded.
                notificationPredicate: (notification) =>
                    !_isForum &&
                    !_building &&
                    defaultScrollNotificationPredicate(notification),
                onRefresh: () => _load(reset: true),
                child: Opacity(
                  opacity: _viewport.hidden && !(_isFloor && _initialLoading)
                      ? 0
                      : 1,
                  child: _readingList(
                    key: _listKey,
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      _isForum ? 12 : 16,
                      !_isForum && !_building ? 48 : 8,
                      _isForum ? 12 : 16,
                      16,
                    ),
                    rowIds: visibleItems.map((p) => '${p['id']}').toList(),
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
                                ForumHeaderCard(
                                  key: _forumIdentityKey,
                                  showBackground: false,
                                  forum: forum,
                                  name: widget.forum!,
                                  onDetails: _openForumDetails,
                                  level: _followed ? _myForumLevel : {},
                                  levelNames: _levelNames,
                                  trailing: _reader.forumFollowUncertain
                                      ? FilledButton.tonal(
                                          onPressed: _reader.forumActionsBusy
                                              ? null
                                              : _refreshForumInfo,
                                          child: Text(_followed ? '签到' : '关注'),
                                        )
                                      : _followed
                                      ? SignButton(
                                          key: ValueKey(
                                            'sign-${AuthStore.instance.activeId}',
                                          ),
                                          api: _api,
                                          enabled:
                                              !_reader.forumActionsBusy &&
                                              !_reader.forumFollowUncertain,
                                          statusRevision:
                                              _reader.forumStatusRevision,
                                          onSigningChanged:
                                              _reader.setForumSigning,
                                          name: widget.forum!,
                                          followed: true,
                                          compact: true,
                                          signed:
                                              flag(sign['is_sign_in']) ||
                                              flag(forum['is_sign_in']),
                                        )
                                      : FilledButton.tonal(
                                          onPressed:
                                              _reader.forumActionsBusy ||
                                                  _forum['id'] == null
                                              ? null
                                              : () => _follow(true),
                                          child: Text(
                                            _reader.forumFollowing
                                                ? '关注中'
                                                : '关注',
                                          ),
                                        ),
                                ),
                                for (final pinned in _pinned)
                                  Padding(
                                    key: ValueKey('pinned-${pinned['id']}'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => ReadingPage(
                                              forum: widget.forum,
                                              threadId: '${pinned['id']}',
                                              title: firstText([
                                                pinned['title'],
                                              ]),
                                              levelNames: _levelNames,
                                              previewThread: {
                                                ...pinned,
                                                'author': _forumUser(
                                                  _users['${pinned['author_id']}'] ??
                                                      object(pinned['author']),
                                                ),
                                              },
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.push_pin_rounded,
                                                size: 14,
                                                color: Colors.white70,
                                                semanticLabel: '置顶',
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  firstText([
                                                    pinned['title'],
                                                  ], '查看置顶帖'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 2),
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
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  12,
                                ),
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
                              if (_building && _reader.loadingPrevious)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              if (_building && _reader.previousFailed)
                                TextButton(
                                  onPressed: _retryLoad,
                                  child: const Text('加载失败，点击重试'),
                                ),
                              if (!_building && _firstPage > 1)
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
                                    : firstText([
                                        _thread['title'],
                                        widget.title,
                                      ]),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontSize: 21,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              if (!_building &&
                                  _result == null &&
                                  _previewThread != null)
                                _threadPreview(),
                              if (_building ||
                                  !visibleItems.any(
                                    (p) => number(p['floor']) == 1,
                                  ))
                                _replyControls(),
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
                      final isFirstFloor =
                          !_isFloor && number(item['floor']) == 1;
                      final card = KeyedSubtree(
                        key: _rowKeys.putIfAbsent(
                          '${item['id']}',
                          () => GlobalKey(),
                        ),
                        child: AnimatedSize(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 420),
                          alignment: Alignment.bottomCenter,
                          child:
                              _removing.contains(
                                userKey(_forumUser(user), item),
                              )
                              ? const SizedBox(width: double.infinity)
                              : _commentCard(item),
                        ),
                      );
                      if (!isFirstFloor) return card;
                      return Column(
                        children: [card, if (!_building) _replyControls()],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readingLayout({required Widget header, required Widget child}) {
    if (_isForum || _building) {
      return Column(
        children: [
          header,
          Expanded(child: child),
        ],
      );
    }
    // Keep the scroll viewport fixed while the toolbar animates above it.
    // SafeArea consumes the status inset once for both the list and toolbar.
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(top: 0, left: 0, right: 0, child: header),
        ],
      ),
    );
  }

  Widget _forumBackground(Widget child) => _isForum
      ? ForumCover(
          forum: _forum,
          radius: 0,
          imageHeight: MediaQuery.paddingOf(context).top + 360,
          child: child,
        )
      : child;

  Widget _threadPreview() {
    final thread = _previewThread!;
    final parts = contentParts(thread['abstract']);
    final user = object(thread['author']);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.isNotEmpty) ...[
            UserHeader(
              user: user,
              subtitle: commentTime(thread['time'] ?? thread['create_time']),
              isOriginalPoster: true,
              showForumLevel: true,
              levelNames: _levelNames,
            ),
            const SizedBox(height: 12),
          ],
          if (parts.isNotEmpty)
            BuildingContent(
              enabled: _building,
              parts: parts,
              child: PostContent(
                parts: parts,
                adaptiveImages: true,
                textStyle: const TextStyle(fontSize: 16, height: 1.55),
              ),
            ),
          // Use the same thumbnail URLs and decode size as the feed so its
          // already decoded images can be displayed while full posts arrive.
          IgnorePointer(child: ThreadThumbnails(thread: thread)),
        ],
      ),
    );
  }

  Widget _replyControls() => Padding(
    key: _sortAnchor,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final filters = SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(_building ? '全部楼层' : '全部回复'),
            ),
            ButtonSegment(value: true, label: Text(_building ? '楼主层' : '只看楼主')),
          ],
          selected: {_onlyAuthor},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
          onSelectionChanged: _busy
              ? null
              : (value) => _changeReplies(onlyAuthor: value.single),
        );
        final sorting = PopupMenuButton<int>(
          enabled: !_busy,
          initialValue: _replySort,
          onSelected: (sort) => _changeReplies(sort: sort),
          itemBuilder: (_) => [
            PopupMenuItem(value: 2, child: Text(_building ? '热门' : '按热度排序')),
            const PopupMenuItem(value: 0, child: Text('正序')),
            const PopupMenuItem(value: 1, child: Text('倒序')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_replySortLabel, style: const TextStyle(fontSize: 12)),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        );
        if (constraints.maxWidth <
            300 * MediaQuery.textScalerOf(context).scale(12) / 12) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              filters,
              Align(alignment: Alignment.centerRight, child: sorting),
            ],
          );
        }
        return Row(children: [filters, const Spacer(), sorting]);
      },
    ),
  );

  void _selectForumCategory(String category, [ForumSection? section]) {
    if (_category == category && _section?.id == section?.id) return;
    setState(() {
      _category = category;
      _section = section;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = section == null ? category : 'section-${section.id}';
      final tabContext = _forumCategoryKeys[key]?.currentContext;
      final target = tabContext?.findRenderObject() as RenderBox?;
      final viewport =
          _forumTabsKey.currentContext?.findRenderObject() as RenderBox?;
      if (target == null || viewport == null || !_forumTabsScroll.hasClients)
        return;
      final center = target
          .localToGlobal(Offset(target.size.width / 2, 0), ancestor: viewport)
          .dx;
      final position = _forumTabsScroll.position;
      final offset = (position.pixels + center - viewport.size.width / 2).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _forumTabsScroll.jumpTo(offset);
    });
  }

  Widget _forumCategoryBar() => SingleChildScrollView(
    key: _forumTabsKey,
    controller: _forumTabsScroll,
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        for (final category in _forumCategories)
          Padding(
            key: _forumCategoryKeys.putIfAbsent(category, () => GlobalKey()),
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              label: Text(category),
              selected: _section == null && _category == category,
              onSelected: (_) => _selectForumCategory(category),
            ),
          ),
        for (final section in forumSections(_result?.data ?? {}))
          Padding(
            key: _forumCategoryKeys.putIfAbsent(
              'section-${section.id}',
              () => GlobalKey(),
            ),
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              label: Text(section.name),
              selected: _section?.id == section.id,
              onSelected: (_) => _selectForumCategory(section.name, section),
            ),
          ),
      ],
    ),
  );

  Widget _readingList({
    Key? key,
    required ScrollController controller,
    required ScrollPhysics physics,
    required EdgeInsets padding,
    required List<String> rowIds,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    if (_isForum) {
      final sections = forumSections(_result?.data ?? {});
      final queries = [
        for (final category in _forumCategories)
          ReadingQuery(forum: widget.forum, category: category),
        for (final section in sections)
          ReadingQuery(
            forum: widget.forum,
            category: section.name,
            section: section,
          ),
      ];
      final selected = _section == null
          ? _forumCategories.indexOf(_category)
          : _forumCategories.length +
                sections.indexWhere((s) => s.id == _section!.id);
      return ForumFeedPager(
        key: ValueKey('forum-feed-${widget.forum}'),
        api: _api,
        primaryReader: _reader,
        loadPrimary: (reset) => _load(reset: reset),
        outerController: controller,
        header: Padding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            0,
          ),
          child: itemBuilder(context, 0),
        ),
        categoryBar: _forumCategoryBar(),
        categories: queries,
        selected: selected < 0 ? 1 : selected,
        onSelected: (index) => _selectForumCategory(
          queries[index].category,
          queries[index].section,
        ),
        levelNames: _levelNames,
        decorateUser: _forumUser,
      );
    }
    final rowIndices = <String, int>{};
    for (var i = 0; i < rowIds.length; i++) {
      rowIndices.putIfAbsent(rowIds[i], () => i + 1);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = ((constraints.maxWidth - 760) / 2).clamp(
          0.0,
          double.infinity,
        );
        return ListView.builder(
          key: key,
          reverse: _building,
          controller: controller,
          physics: physics,
          padding: padding.copyWith(
            left: padding.left + gutter,
            right: padding.right + gutter,
          ),
          itemCount: itemCount,
          findChildIndexCallback: (key) {
            if (key == const ValueKey('reading-header')) return 0;
            if (key == const ValueKey('reading-footer')) return itemCount - 1;
            if (key is ValueKey<String>) {
              return rowIndices[key.value];
            }
            return null;
          },
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey(
              index == 0
                  ? 'reading-header'
                  : index == itemCount - 1
                  ? 'reading-footer'
                  : rowIds[index - 1],
            ),
            child: itemBuilder(context, index),
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    if (_building && (_reader.loadingPrevious || _reader.previousFailed)) {
      return const SizedBox.shrink();
    }
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
            FilledButton.tonal(onPressed: _retryLoad, child: const Text('重试')),
          ],
        ),
      );
    }
    final warning = firstText([_result?.data['forum_parse_warning']]);
    if (_items.isEmpty && _pinned.isEmpty && !_hasMore && warning.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_isForum ? '当前分类暂无帖子' : '暂时没有可显示的内容')),
      );
    }
    final pagination = Center(
      child: _hasMore
          ? TextButton(onPressed: _load, child: const Text('加载下一页'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_building ? '已经到楼顶了' : '已经到底了'),
            ),
    );
    if (!_isForum || warning.isEmpty) return pagination;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(warning, textAlign: TextAlign.center),
        ),
        pagination,
      ],
    );
  }
}
