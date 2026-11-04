import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/tieba_api.dart';

enum ReadingScene { forum, thread, replies }

/// Network selection, captured once per request; never reads live widget fields.
class ReadingQuery {
  const ReadingQuery({
    this.forum,
    this.threadId,
    this.postId,
    this.category = '最新回复',
    this.section,
    this.hot = false,
    this.descending = false,
    this.onlyAuthor = false,
  });
  final String? forum, threadId, postId;
  final String category;
  final ForumSection? section;
  final bool hot, descending, onlyAuthor;
  ReadingScene get scene => threadId == null
      ? ReadingScene.forum
      : postId == null
      ? ReadingScene.thread
      : ReadingScene.replies;
}

class ReadingData {
  const ReadingData({
    this.result,
    this.items = const [],
    this.pinned = const [],
    this.users = const {},
    this.thread = const {},
    this.forum = const {},
    this.parent = const {},
    this.page = 0,
    this.firstPage = 1,
    this.hasMore = true,
  });

  final TiebaPage? result;
  final List<Json> items, pinned;
  final Map<String, Json> users;
  final Json thread, forum, parent;
  final int page, firstPage;
  final bool hasMore;

  ReadingData copyWith({
    List<Json>? items,
    Json? thread,
    Json? forum,
    Json? parent,
  }) => ReadingData(
    result: result,
    items: items == null ? this.items : List.unmodifiable(items),
    pinned: pinned,
    users: users,
    thread: thread == null ? this.thread : Map.unmodifiable(thread),
    forum: forum == null ? this.forum : Map.unmodifiable(forum),
    parent: parent == null ? this.parent : Map.unmodifiable(parent),
    page: page,
    firstPage: firstPage,
    hasMore: hasMore,
  );

  Json toCache() => {
    'items': items,
    'users': users,
    'thread': thread,
    'forum': forum,
    'parent': parent,
    'data': result?.data,
    'page': page,
    'first_page': firstPage,
    'more': hasMore,
  };

  factory ReadingData.fromCache(Json cache) => ReadingData(
    result: TiebaPage(object(cache['data'])),
    items: List.unmodifiable(objects(cache['items'])),
    users: Map.unmodifiable(
      object(cache['users']).map((key, value) => MapEntry(key, object(value))),
    ),
    thread: Map.unmodifiable(object(cache['thread'])),
    forum: Map.unmodifiable(object(cache['forum'])),
    parent: Map.unmodifiable(object(cache['parent'])),
    page: number(cache['page']),
    firstPage: number(cache['first_page']),
    hasMore: flag(cache['more']),
  );
}

class ReadingLoad {
  const ReadingLoad(this.revision, this.unsupportedHot);
  final int revision;
  final bool unsupportedHot;
}

/// Owns the loaded content and pagination. No scroll, frame, or widget objects.
class ReadingController extends ChangeNotifier {
  ReadingController(
    this._api, {
    Json parent = const {},
    ReadingData? initialData,
  }) : _data = initialData ?? ReadingData(parent: Map.unmodifiable(parent));

  final TiebaApi _api;
  ReadingData _data;
  int _revision = 0;
  bool _busy = false, _disposed = false;
  bool _previous = false;
  bool? _confirmedFollowed;
  bool _forumFollowing = false, _forumSigning = false;
  bool _forumRefreshing = false;
  bool _forumFollowUncertain = false;
  int _forumActionRevision = 0, _forumRefreshRevision = 0;
  int _forumStatusRevision = 0;
  String? _error;
  ReadingData get data => _data;
  int get revision => _revision;
  bool get busy => _busy;
  String? get error => _error;
  bool get loadingPrevious => _previous && _busy;
  bool get previousFailed => _previous && _error != null;
  bool accepts(int revision) => !_disposed && revision == _revision;
  bool get forumFollowed =>
      flag(_data.forum['is_like'] ?? _data.forum['is_liked']);
  bool get forumFollowing => _forumFollowing;
  bool get forumActionsBusy =>
      _forumFollowing || _forumSigning || _forumRefreshing;
  bool get forumFollowUncertain => _forumFollowUncertain;
  int get forumStatusRevision => _forumStatusRevision;

  void _resetForumActions() {
    _forumActionRevision++;
    _forumRefreshRevision++;
    _confirmedFollowed = null;
    _forumFollowing = _forumSigning = _forumFollowUncertain = false;
    _forumRefreshing = false;
  }

  Json _mergeForum(Json forum) {
    final merged = {..._data.forum, ...forum};
    final followed =
        _confirmedFollowed ??
        (forum.containsKey('is_like') || forum.containsKey('is_liked')
            ? flag(forum['is_like'] ?? forum['is_liked'])
            : null);
    return {
      ...merged,
      if (followed != null) ...{
        'is_like': followed ? 1 : 0,
        'is_liked': followed ? 1 : 0,
      },
    };
  }

  void _confirmForumRead(Json forum, int actionRevision) {
    if (actionRevision != _forumActionRevision || _forumFollowing) return;
    if (forum.containsKey('is_like') || forum.containsKey('is_liked')) {
      _forumFollowUncertain = false;
      _forumStatusRevision++;
    }
  }

  void setForumSigning(bool signing) {
    if (_disposed || _forumSigning == signing) return;
    _forumSigning = signing;
    notifyListeners();
  }

  Future<bool> changeForumFollowed(String name, bool followed) async {
    if (_disposed || forumActionsBusy || _forumFollowUncertain) return false;
    final id = firstText([_data.forum['id']]);
    if (id.isEmpty) throw const TiebaException('吧信息尚未加载，请刷新后重试');
    if (followed == forumFollowed) return false;
    final action = ++_forumActionRevision;
    _forumFollowing = true;
    notifyListeners();
    bool current() => !_disposed && action == _forumActionRevision;
    try {
      await _api.followForum(name, id, undo: !followed);
      if (!current()) return false;
      setFollowed(followed);
      return true;
    } catch (error) {
      if (!current()) return false;
      if (error is TiebaException && error.uncertain) {
        _confirmedFollowed = null;
        _forumFollowUncertain = true;
      }
      rethrow;
    } finally {
      if (current()) {
        _forumFollowing = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshForum(String name) async {
    if (_disposed || forumActionsBusy) return;
    final action = _forumActionRevision;
    final refresh = ++_forumRefreshRevision;
    _forumRefreshing = true;
    notifyListeners();
    bool current() =>
        !_disposed &&
        action == _forumActionRevision &&
        refresh == _forumRefreshRevision;
    try {
      final result = await _api.forum(name, 1, category: '热门');
      if (!current()) return;
      final forum = object(result.data['forum']);
      _confirmForumRead(forum, action);
      updateForum(forum);
    } finally {
      if (current()) {
        _forumRefreshing = false;
        notifyListeners();
      }
    }
  }

  int beginExternalLoad() {
    _previous = false;
    _revision++;
    _busy = true;
    _error = null;
    notifyListeners();
    return _revision;
  }

  void finishExternalLoad(int revision) {
    if (!accepts(revision)) return;
    _busy = false;
    notifyListeners();
  }

  void clear() {
    _revision++;
    _resetForumActions();
    _data = const ReadingData();
    _busy = false;
    _error = null;
    notifyListeners();
  }

  void clearItems() {
    _revision++;
    _data = ReadingData(
      result: _data.result,
      thread: _data.thread,
      forum: _data.forum,
      pinned: _data.pinned,
      users: _data.users,
      parent: _data.parent,
    );
    _busy = false;
    _error = null;
    notifyListeners();
  }

  void restore(Json cache) {
    _revision++;
    _resetForumActions();
    _data = ReadingData.fromCache(cache);
    _busy = false;
    _error = null;
    notifyListeners();
  }

  void setFollowed(bool followed) {
    // A confirmed write wins over eventually consistent FRS snapshots for this
    // page/account. clear() drops it when the account changes.
    _confirmedFollowed = followed;
    _data = _data.copyWith(
      forum: {
        ..._data.forum,
        'is_like': followed ? 1 : 0,
        'is_liked': followed ? 1 : 0,
      },
    );
    notifyListeners();
  }

  void updateForum(Json forum) {
    _data = _data.copyWith(forum: _mergeForum(forum));
    notifyListeners();
  }

  void setPoll(Json poll) {
    _data = _data.copyWith(thread: {..._data.thread, 'poll_info': poll});
    notifyListeners();
  }

  void updateLike(Json source, Json patch, {required bool firstFloor}) {
    if (_disposed) return;
    final matchesThread = identical(source, _data.thread);
    final matchesParent = identical(source, _data.parent);
    if (!matchesThread &&
        !matchesParent &&
        !_data.items.any((item) => identical(item, source)))
      return;
    _data = _data.copyWith(
      thread: firstFloor ? {..._data.thread, ...patch} : null,
      parent: matchesParent ? {..._data.parent, ...patch} : null,
      items: [
        for (final item in _data.items)
          if (identical(item, source) ||
              (firstFloor && number(item['floor']) == 1))
            {...item, ...patch}
          else
            item,
      ],
    );
    notifyListeners();
  }

  List<Json> _applyFloors(List<Json> items, Map<String, int> floors) => [
    for (final post in items)
      if (floors['${post['id']}'] case final int floor)
        {...post, if (floor > 0) 'floor': floor, 'floor_pending': false}
      else
        post,
  ];

  Future<ReadingLoad?> load(
    ReadingQuery query, {
    bool reset = false,
    bool previous = false,
    bool preserveFirst = false,
    int? pageOverride,
    String? targetPost,
    String? targetReply,
    TiebaPage? initialPage,
  }) async {
    if (_disposed || (_busy && !reset)) return null;
    if (previous && (reset || _data.firstPage <= 1)) return null;
    var base = _data;
    final forumAction = _forumActionRevision;
    final revision = beginExternalLoad();
    _previous = previous;
    final nextPage = previous
        ? base.firstPage - 1
        : pageOverride ?? (reset ? 1 : base.page + 1);
    final floors = <String, int>{};
    try {
      var result =
          initialPage ??
          await switch (query.scene) {
            ReadingScene.forum => _api.forum(
              query.forum!,
              nextPage,
              category: query.category,
              section: query.section,
              forumId: '${base.forum['id'] ?? ''}',
              lastThreadId: reset || base.items.isEmpty
                  ? '0'
                  : '${base.items.last['id']}',
            ),
            ReadingScene.replies => _api.floor(
              query.threadId!,
              query.postId!,
              nextPage,
              targetReply: targetReply,
            ),
            ReadingScene.thread => _api.thread(
              query.threadId!,
              nextPage,
              onlyAuthor: query.onlyAuthor,
              hot: query.hot,
              descending: query.descending,
              targetPost: targetPost,
              onFloorNumbers: (resolved) {
                if (!accepts(revision) || !query.hot) return;
                floors.addAll(resolved);
                _data = _data.copyWith(
                  items: _applyFloors(_data.items, floors),
                );
                notifyListeners();
              },
            ),
          };
      if (!accepts(revision)) return null;
      base = _data;
      if (query.scene == ReadingScene.forum && query.section != null) {
        result = TiebaPage({
          ...result.data,
          'forum': base.forum,
          'nav_tab_info': base.result?.data['nav_tab_info'],
        });
      }
      final unsupportedHot =
          query.scene == ReadingScene.thread &&
          query.hot &&
          number(result.data['sort_type']) != 2;
      final actualPage = number(
        object(result.data['page'])['current_page'] ??
            object(result.data['page'])['cur_page'],
      );
      final page = actualPage > 0 ? actualPage : nextPage;
      if (previous && page >= base.firstPage) {
        throw const FormatException('Previous page did not advance');
      }
      var incoming = switch (query.scene) {
        ReadingScene.forum => result.threads,
        ReadingScene.thread => result.posts,
        ReadingScene.replies => result.replies,
      };
      if (query.scene != ReadingScene.forum) {
        incoming = [
          for (final item in incoming) {...item, '_reading_page': page},
        ];
      }
      var pins = reset && query.section == null
          ? <Json>[]
          : List<Json>.of(base.pinned);
      if (query.scene == ReadingScene.forum) {
        pins.addAll(incoming.where((item) => flag(item['is_top'])));
        final ids = <String>{};
        pins = pins.where((item) => ids.add('${item['id']}')).toList();
        incoming = incoming.where((item) => !flag(item['is_top'])).toList();
      }
      final first = preserveFirst
          ? base.items.where((post) => number(post['floor']) == 1).toList()
          : <Json>[];
      if (first.isNotEmpty) {
        incoming = [
          ...first,
          ...incoming.where(
            (post) =>
                number(post['floor']) != 1 &&
                !first.any((old) => old['id'] == post['id']),
          ),
        ];
      }
      final ids = (reset ? <Json>[] : base.items)
          .map((p) => '${p['id']}')
          .toSet();
      var items = [
        if (previous) ...incoming.where((post) => ids.add('${post['id']}')),
        if (!reset) ...base.items,
        if (!previous) ...incoming.where((post) => ids.add('${post['id']}')),
      ];
      if (query.scene == ReadingScene.forum) {
        if (query.section == null && query.category == '最新回复') {
          items.sort((a, b) => lastReplyTime(b).compareTo(lastReplyTime(a)));
        } else if (query.section == null && query.category == '最新发布') {
          items.sort(
            (a, b) =>
                number(b['create_time']).compareTo(number(a['create_time'])),
          );
        }
      }
      final thread = <String, dynamic>{
        ...((reset && !preserveFirst) || base.thread.isEmpty
            ? object(result.data['thread'])
            : base.thread),
      };
      if (query.scene == ReadingScene.thread) {
        items = _applyFloors(items, floors);
        for (final post in items.where((post) => number(post['floor']) == 1)) {
          if (thread['agree'] is! Map && post['agree'] is Map)
            thread['agree'] = post['agree'];
        }
        items = [
          ...items.where((p) => number(p['floor']) == 1),
          ...items.where((p) => number(p['floor']) != 1),
        ];
      }
      final parent = object(result.data['post']);
      final incomingForum = object(result.data['forum']);
      if (query.scene == ReadingScene.forum && reset) {
        _confirmForumRead(incomingForum, forumAction);
      }
      _data = ReadingData(
        result: previous ? base.result : result,
        items: List.unmodifiable(items),
        pinned: List.unmodifiable(pins),
        users: Map.unmodifiable({
          if (!reset || query.section != null) ...base.users,
          ...result.users,
        }),
        thread: Map.unmodifiable(thread),
        forum: Map.unmodifiable(
          _mergeForum(reset || base.forum.isEmpty ? incomingForum : base.forum),
        ),
        parent: query.scene == ReadingScene.replies && parent.isNotEmpty
            ? Map.unmodifiable({
                ...base.parent,
                ...parent,
                'author': {
                  ...object(base.parent['author']),
                  ...object(parent['author']),
                },
              })
            : base.parent,
        page: previous ? base.page : page,
        firstPage: reset || previous ? page : base.firstPage,
        hasMore: previous ? base.hasMore : result.hasMore,
      );
      return ReadingLoad(revision, unsupportedHot);
    } catch (error) {
      if (accepts(revision)) {
        _error = switch (error) {
          TimeoutException() => '请求超时，请检查网络后重试。',
          SocketException() => '无法连接贴吧，请检查网络后重试。',
          TiebaException() => error.message,
          _ => '加载失败，请检查网络后重试。',
        };
      }
      return null;
    } finally {
      if (accepts(revision)) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
