import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalStore extends ChangeNotifier {
  LocalStore._();
  static final instance = LocalStore._();
  late SharedPreferences _prefs;
  Future<void> _pendingWrite = Future<void>.value();

  // Compute each update after the preceding write has committed, so rapid
  // visits, block actions and history clearing cannot overwrite one another.
  Future<void> _mutate(Future<void> Function() action) {
    final result = _pendingWrite.then((_) => action());
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  List<String> recent = [];
  Map<String, String> blockedForums = {};
  Map<String, String> blockedUsers = {};
  List<String> forumKeywords = [];
  List<Json> history = [];
  Map<String, dynamic> _reading = {};
  final _readingPages = <String, Json>{};
  Json? readingPage(String account, String tid, {String parent = ''}) {
    final key = '$account:$tid:$parent';
    final page = _readingPages.remove(key);
    if (page != null) _readingPages[key] = page;
    return page;
  }

  void rememberReadingPage(
    String account,
    String tid,
    Json page, {
    String parent = '',
  }) {
    final key = '$account:$tid:$parent';
    _readingPages.remove(key);
    // Keep several recently read pages without retaining an unbounded long thread.
    final items = page['items'];
    if (items is List && items.length > 240) return;
    _readingPages[key] = page;
    while (_readingPages.length > 8 ||
        _readingPages.values.fold<int>(
              0,
              (n, p) =>
                  n + (p['items'] is List ? (p['items'] as List).length : 0),
            ) >
            700) {
      _readingPages.remove(_readingPages.keys.first);
    }
  }

  void clearReadingPages() => _readingPages.clear();
  Json readingPosition(String tid, {String parent = ''}) =>
      object(_reading['$tid:$parent']);
  Future<void> saveReadingPosition(
    String tid,
    Json position, {
    String parent = '',
  }) => _mutate(() async {
    final key = '$tid:$parent';
    _reading.remove(key);
    _reading[key] = position;
    while (_reading.length > 200) {
      _reading.remove(_reading.keys.first);
    }
    await _prefs.setString('reading_positions', jsonEncode(_reading));
  });

  bool buildingMode = false;
  Future<void> setBuildingMode(bool value) => _mutate(() async {
    if (!await _prefs.setBool('building_mode', value)) {
      throw StateError('无法保存盖楼模式');
    }
    buildingMode = value;
    clearReadingPages();
    notifyListeners();
  });

  String themePreference = 'system';
  int themeColor = 0xff246BCE;
  int buttonColor = 0xff246BCE;
  int backgroundColor = 0xffF7F8FA;
  bool backgroundFollowsSystem = false;
  final appearanceRevision = ValueNotifier<int>(0);

  int resolvedBackgroundColor(Brightness brightness) => backgroundFollowsSystem
      ? (brightness == Brightness.dark ? 0xff000000 : 0xffffffff)
      : backgroundColor;

  void previewButtonColor(int value) {
    buttonColor = value;
    appearanceRevision.value++;
  }

  Future<void> setButtonColor(int value) => _mutate(() async {
    if (!await _prefs.setInt('button_color', value)) {
      throw StateError('无法保存按钮颜色');
    }
    previewButtonColor(value);
    notifyListeners();
  });

  void previewBackgroundColor(int value, {bool followSystem = false}) {
    backgroundColor = value;
    backgroundFollowsSystem = followSystem;
    appearanceRevision.value++;
  }

  Future<void> setBackgroundColor(int value, {bool followSystem = false}) =>
      _mutate(() async {
        if (!await _prefs.setInt('background_color', value)) {
          throw StateError('无法保存背景颜色');
        }
        if (!await _prefs.setBool('background_follows_system', followSystem)) {
          throw StateError('无法保存背景切换方式');
        }
        previewBackgroundColor(value, followSystem: followSystem);
        notifyListeners();
      });

  void previewThemeColor(int value) {
    themeColor = value;
    appearanceRevision.value++;
  }

  Future<void> setThemeColor(int value) => _mutate(() async {
    if (!await _prefs.setInt('theme_color', value)) {
      throw StateError('无法保存强调色');
    }
    previewThemeColor(value);
    notifyListeners();
  });

  Map<String, String> _signedForums = {};
  static String _signDay(DateTime now) => '${now.year}-${now.month}-${now.day}';
  bool forumSigned(String account, String name, {DateTime? now}) =>
      account.isNotEmpty &&
      _signedForums['$account:${name.toLowerCase()}'] ==
          _signDay(now ?? DateTime.now());
  Future<void> markForumSigned(String account, String name, {DateTime? now}) =>
      _mutate(() async {
        if (account.isEmpty || name.isEmpty) return;
        _signedForums['$account:${name.toLowerCase()}'] = _signDay(
          now ?? DateTime.now(),
        );
        notifyListeners();
        await _prefs.setString('signed_forums', jsonEncode(_signedForums));
      });

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    for (final key
        in _prefs
            .getKeys()
            .where((key) => key.startsWith('reply_draft_'))
            .toList()) {
      await _prefs.remove(key);
    }
    try {
      _reading = object(
        jsonDecode(_prefs.getString('reading_positions') ?? '{}'),
      );
    } catch (_) {
      _reading = {};
    }
    buildingMode = _prefs.getBool('building_mode') ?? false;
    final theme = _prefs.getString('theme_mode');
    backgroundFollowsSystem =
        _prefs.getBool('background_follows_system') ?? false;
    backgroundColor =
        (_prefs.getInt('background_color') ??
            (theme == 'dark' ? 0xff181818 : 0xffF7F8FA)) |
        0xff000000;
    themeColor = (_prefs.getInt('theme_color') ?? 0xff246BCE) | 0xff000000;
    buttonColor = (_prefs.getInt('button_color') ?? themeColor) | 0xff000000;
    // Import the old shared color once; later launches must not follow changes
    // to the independently saved accent color.
    if (!_prefs.containsKey('button_color')) {
      await _prefs.setInt('button_color', buttonColor);
    }
    themePreference = ['light', 'dark', 'system'].contains(theme)
        ? theme!
        : 'system';
    recent = _prefs.getStringList('recent_forums') ?? [];
    forumKeywords = _prefs.getStringList('forum_keywords') ?? [];
    try {
      _signedForums = object(
        jsonDecode(_prefs.getString('signed_forums') ?? '{}'),
      ).map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      _signedForums = {};
    }
    try {
      history = objects(jsonDecode(_prefs.getString('thread_history') ?? '[]'));
    } catch (_) {
      history = [];
    }
    try {
      blockedForums = object(
        jsonDecode(_prefs.getString('blocked_forums') ?? '{}'),
      ).map((k, v) => MapEntry(k, '$v'));
      blockedUsers = object(
        jsonDecode(_prefs.getString('blocked_users') ?? '{}'),
      ).map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      blockedForums = {};
      blockedUsers = {};
    }
  }

  Future<void> visit(String name) => _mutate(() async {
    if (name.trim().isEmpty) return;
    if (recent.isNotEmpty && recent.first == name) return;
    final updated = [name, ...recent.where((n) => n != name)].take(20).toList();
    await _prefs.setStringList('recent_forums', updated);
    recent = updated;
    notifyListeners();
  });

  bool hidden(Json thread, Json user) {
    if (blockedUsers.isNotEmpty &&
        blockedUsers.containsKey(userKey(user, thread)))
      return true;
    if (blockedForums.isEmpty && forumKeywords.isEmpty) return false;
    final name = threadForumName(thread).toLowerCase();
    return blockedForums.containsKey(name) ||
        forumKeywords.any((word) => name.contains(word.toLowerCase()));
  }

  bool userBlocked(Json user, [Json post = const {}]) =>
      blockedUsers.isNotEmpty && blockedUsers.containsKey(userKey(user, post));

  Future<void> setTheme(String mode) => _mutate(() async {
    if (!['light', 'dark', 'system'].contains(mode)) return;
    await _prefs.setString('theme_mode', mode);
    themePreference = mode;
    notifyListeners();
  });

  Future<void> visitThread(String id, String title, String forum) =>
      _mutate(() async {
        if (id.isEmpty) return;
        final updated = [
          {
            'id': id,
            'title': title,
            'forum': forum,
            'viewed_at': DateTime.now().millisecondsSinceEpoch,
          },
          ...history.where((entry) => '${entry['id']}' != id),
        ].take(200).toList();
        await _prefs.setString('thread_history', jsonEncode(updated));
        history = updated;
        notifyListeners();
      });

  Future<void> clearHistory() => _mutate(() async {
    clearReadingPages();
    await _prefs.remove('thread_history');
    await _prefs.remove('recent_forums');
    await _prefs.remove('reading_positions');
    _reading = {};
    history = [];
    recent = [];
    notifyListeners();
  });

  Future<void> addForumKeyword(String raw) => _mutate(() async {
    final word = raw.trim();
    if (word.isEmpty ||
        forumKeywords.any((v) => v.toLowerCase() == word.toLowerCase())) {
      return;
    }
    final updated = [...forumKeywords, word];
    await _prefs.setStringList('forum_keywords', updated);
    forumKeywords = updated;
    notifyListeners();
  });

  Future<void> removeForumKeyword(String word) => _mutate(() async {
    final updated = forumKeywords.where((v) => v != word).toList();
    await _prefs.setStringList('forum_keywords', updated);
    forumKeywords = updated;
    notifyListeners();
  });

  Future<void> blockForum(String name) => _mutate(() async {
    final updated = Map<String, String>.of(blockedForums)
      ..remove(name.toLowerCase());
    updated[name.toLowerCase()] = name;
    await _prefs.setString('blocked_forums', jsonEncode(updated));
    blockedForums = updated;
    notifyListeners();
  });

  Future<void> blockUser(String key, String name) => _mutate(() async {
    if (key.isEmpty) return;
    final updated = Map<String, String>.of(blockedUsers)..remove(key);
    updated[key] = name;
    await _prefs.setString('blocked_users', jsonEncode(updated));
    blockedUsers = updated;
    notifyListeners();
  });

  Future<void> unblock(String key, {required bool forum}) => _mutate(() async {
    final updated = Map<String, String>.of(forum ? blockedForums : blockedUsers)
      ..remove(key);
    await _prefs.setString(
      forum ? 'blocked_forums' : 'blocked_users',
      jsonEncode(updated),
    );
    if (forum) {
      blockedForums = updated;
    } else {
      blockedUsers = updated;
    }
    notifyListeners();
  });
}
