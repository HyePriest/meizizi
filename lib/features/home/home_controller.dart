import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/auth_store.dart';
import '../../data/local_store.dart';
import '../../data/tieba_api.dart';

/// One committed snapshot per tab. Views never maintain a second list cache.
class HomeFeedState {
  const HomeFeedState({
    this.items = const [],
    this.users = const {},
    this.page = 0,
    this.hasMore = true,
    this.busy = false,
    this.bottomRefresh = false,
    this.retryReset = true,
    this.error,
  });

  final List<Json> items;
  final Map<String, Json> users;
  final int page;
  final bool hasMore, busy, bottomRefresh, retryReset;
  final String? error;

  HomeFeedState loading({required bool reset, required bool fromBottom}) =>
      HomeFeedState(
        items: items,
        users: users,
        page: page,
        hasMore: hasMore,
        busy: true,
        bottomRefresh: fromBottom,
        retryReset: reset,
      );

  HomeFeedState stopped({String? error}) => HomeFeedState(
    items: items,
    users: users,
    page: page,
    hasMore: hasMore,
    retryReset: retryReset,
    error: error,
  );
}

class HomeController extends ChangeNotifier {
  HomeController({
    TiebaApi? api,
    AuthStore? auth,
    LocalStore? store,
    bool? usePreload,
  }) : _api = api ?? TiebaApi(),
       _auth = auth ?? AuthStore.instance,
       _store = store ?? LocalStore.instance,
       _usePreload = usePreload ?? api == null {
    _auth.addListener(_accountChanged);
    _seedInitialHome();
  }

  static Future<TiebaPage>? _preloadedHome;
  static TiebaPage? _preloadedResult;
  static String? _preloadedAccount;

  /// Starts fetching page 1 of the home feed before the first frame so the
  /// native splash screen overlaps network latency.
  static Future<TiebaPage?> preloadHome({TiebaApi? api, AuthStore? auth}) {
    final resolvedAuth = auth ?? AuthStore.instance;
    final account = resolvedAuth.activeId;
    final ownsApi = api == null;
    final client = api ?? TiebaApi();
    final completer = Completer<TiebaPage>();
    _preloadedAccount = account;
    _preloadedResult = null;
    _preloadedHome = completer.future;
    // Prevent unhandled async errors if the preload is discarded or times out.
    unawaited(completer.future.then<void>((_) {}, onError: (_) {}));

    client
        .home(1)
        .then(
          (page) {
            if (identical(_preloadedHome, completer.future) &&
                _preloadedAccount == account) {
              _preloadedResult = page;
            }
            completer.complete(page);
          },
          onError: (Object error, StackTrace stack) {
            completer.completeError(error, stack);
          },
        )
        .whenComplete(() {
          if (ownsApi) client.close();
        });

    return completer.future.then<TiebaPage?>(
      (page) => page,
      onError: (_) => null,
    );
  }

  static void clearPreload() {
    _preloadedHome = null;
    _preloadedResult = null;
    _preloadedAccount = null;
  }

  final TiebaApi _api;
  final AuthStore _auth;
  final LocalStore _store;
  final bool _usePreload;
  final _feeds = <int, HomeFeedState>{};
  int _tab = 0, _revision = 0, _accountEpoch = 0;
  bool _disposed = false, _holdResult = false;
  HomeFeedState? _pending;

  static ({List<Json> items, Map<String, Json> users, bool hasMore})
  _decodeHomePage(TiebaPage result) {
    final incoming = result.threads
        .where((t) => !t.containsKey('lego_card'))
        .toList();
    final ids = <String>{};
    final items = incoming.where((item) => ids.add('${item['id']}')).toList();
    final hasMore = result.data.containsKey('has_more')
        ? flag(result.data['has_more'])
        : result.data.containsKey('page')
        ? result.hasMore
        : objects(result.data['thread_list']).isNotEmpty;
    return (items: items, users: result.users, hasMore: hasMore);
  }

  void _seedInitialHome() {
    final account = _auth.activeId;
    if (_usePreload &&
        _preloadedResult != null &&
        _preloadedAccount == account) {
      final result = _preloadedResult!;
      clearPreload();
      final decoded = _decodeHomePage(result);
      _feeds[0] = HomeFeedState(
        items: List.unmodifiable(decoded.items),
        users: Map.unmodifiable(decoded.users),
        page: 1,
        hasMore: decoded.hasMore,
      );
      if (decoded.items.isNotEmpty) {
        unawaited(_store.saveHomeFeedCache(account, decoded.items, decoded.users));
      }
      return;
    }
    final cached = _store.cachedHomeFeed(account);
    if (cached != null) {
      // Treat restored cache as page 1 so entering the app never auto-refreshes
      // and yanks posts away; scrolling down appends page 2, and pull-to-refresh
      // explicitly fetches a fresh list.
      _feeds[0] = HomeFeedState(
        items: cached.items,
        users: cached.users,
        page: 1,
        hasMore: true,
      );
    }
  }

  int get tab => _tab;
  int get revision => _revision;
  int get accountEpoch => _accountEpoch;
  HomeFeedState get state => _feeds[_tab] ?? const HomeFeedState();
  bool get canLoadMore =>
      _tab != 2 && !state.busy && state.hasMore && state.error == null;

  void updateLike(Json source, Json patch) {
    if (_disposed || !state.items.any((item) => identical(item, source)))
      return;
    final current = state;
    _publish(
      HomeFeedState(
        items: List.unmodifiable([
          for (final item in current.items)
            if (identical(item, source)) {...item, ...patch} else item,
        ]),
        users: current.users,
        page: current.page,
        hasMore: current.hasMore,
        busy: current.busy,
        bottomRefresh: current.bottomRefresh,
        retryReset: current.retryReset,
        error: current.error,
      ),
    );
  }

  void _publish(HomeFeedState next) {
    _feeds[_tab] = next;
    notifyListeners();
  }

  bool _accepts(int revision) => !_disposed && revision == _revision;

  void _invalidate() {
    _revision++;
    _holdResult = false;
    _pending = null;
    if (state.busy) _feeds[_tab] = state.stopped();
  }

  void selectTab(int tab) {
    if (_disposed || tab == _tab) return;
    _invalidate();
    _tab = tab;
    notifyListeners();
    if (tab != 2 && state.page == 0) load(reset: true);
  }

  void _accountChanged() {
    _invalidate();
    if (_preloadedAccount != _auth.activeId) clearPreload();
    _accountEpoch++;
    _feeds.clear();
    if (_auth.isGuest && _tab == 1) _tab = 0;
    if (_tab == 0) {
      final cached = _store.cachedHomeFeed(_auth.activeId);
      if (cached != null) {
        _feeds[0] = HomeFeedState(
          items: cached.items,
          users: cached.users,
          page: 1,
          hasMore: true,
        );
      }
    }
    notifyListeners();
    if (_tab != 2 && state.page == 0) load(reset: true);
  }

  /// The UI releases its reveal gate; no animation Future enters the data layer.
  void reveal(int revision) {
    if (!_accepts(revision)) return;
    _holdResult = false;
    final next = _pending;
    _pending = null;
    if (next != null) _publish(next);
  }

  /// User interaction cancels this refresh rather than later stealing position.
  void cancelBottomRefresh() {
    if (_disposed || !state.bottomRefresh) return;
    _invalidate();
    notifyListeners();
  }

  Future<void> load({bool reset = false, bool fromBottom = false}) async {
    if (_disposed || _tab == 2 || (!reset && (state.busy || !state.hasMore)))
      return;
    var base = state;
    final revision = ++_revision;
    final tab = _tab;
    final nextPage = reset ? 1 : base.page + 1;
    _pending = null;
    _holdResult = fromBottom;
    _publish(base.loading(reset: reset, fromBottom: fromBottom));

    try {
      List<Json> incoming;
      Map<String, Json> users = {};
      bool hasMore;
      if (tab == 1) {
        if (!_auth.isLoggedIn) {
          _publish(const HomeFeedState(hasMore: false));
          return;
        }
        final result = await _api.followedForums(nextPage);
        incoming = result.items;
        hasMore = result.hasMore;
      } else {
        final TiebaPage result;
        if (reset &&
            _usePreload &&
            _preloadedHome != null &&
            _preloadedAccount == _auth.activeId) {
          final pending = _preloadedHome!;
          clearPreload();
          result = await pending;
        } else {
          result = await _api.home(nextPage);
        }
        final decoded = _decodeHomePage(result);
        incoming = decoded.items;
        users = decoded.users;
        hasMore = decoded.hasMore;
      }
      if (!_accepts(revision)) return;
      base = state;

      final items = reset ? <Json>[] : List<Json>.of(base.items);
      String identity(Json item) =>
          tab == 1 ? forumName(item) : '${item['id']}';
      final ids = items.map(identity).toSet();
      items.addAll(incoming.where((item) => ids.add(identity(item))));
      final mergedUsers = Map<String, Json>.unmodifiable({
        if (!reset) ...base.users,
        ...users,
      });
      final next = HomeFeedState(
        items: List.unmodifiable(items),
        users: mergedUsers,
        page: nextPage,
        hasMore: hasMore,
        retryReset: reset,
      );
      if (tab == 0 && reset && items.isNotEmpty) {
        unawaited(_store.saveHomeFeedCache(_auth.activeId, items, mergedUsers));
      }
      if (_holdResult) {
        _pending = next;
      } else {
        _publish(next);
      }
    } catch (error) {
      if (!_accepts(revision)) return;
      _pending = null;
      _holdResult = false;
      _publish(
        state.stopped(
          error: error is TiebaException ? error.message : '加载失败，请检查网络后重试',
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    _auth.removeListener(_accountChanged);
    _api.close();
    super.dispose();
  }
}
