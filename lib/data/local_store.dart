import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'serial_tasks.dart';

/// SharedPreferences keys. These names are the on-disk format: never rename.
abstract final class _Keys {
  static const replyDraftPrefix = 'reply_draft_';
  static const readingPositions = 'reading_positions';
  static const buildingMode = 'building_mode';
  static const themeMode = 'theme_mode';
  static const themeColor = 'theme_color';
  static const buttonColor = 'button_color';
  static const backgroundColor = 'background_color';
  static const backgroundFollowsSystem = 'background_follows_system';
  static const recentForums = 'recent_forums';
  static const forumKeywords = 'forum_keywords';
  static const signedForums = 'signed_forums';
  static const threadHistory = 'thread_history';
  static const blockedForums = 'blocked_forums';
  static const blockedUsers = 'blocked_users';
}

const _defaultAccentColor = 0xff246BCE;
const _themeModes = ['light', 'dark', 'system'];

class LocalStore extends ChangeNotifier {
  LocalStore._();
  static final instance = LocalStore._();
  late SharedPreferences _prefs;

  // Compute each update after the preceding write has committed, so rapid
  // visits, block actions and history clearing cannot overwrite one another.
  final _writes = SerialTasks();
  Future<void> _mutate(Future<void> Function() action) => _writes.run(action);

  /// Reads a JSON value saved under [key], or [fallback] when it is missing
  /// or unreadable.
  T _readJson<T>(
    String key,
    String empty,
    T Function(dynamic) convert,
    T fallback,
  ) {
    try {
      return convert(jsonDecode(_prefs.getString(key) ?? empty));
    } catch (_) {
      return fallback;
    }
  }

  static Map<String, String> _stringMap(dynamic value) =>
      object(value).map((k, v) => MapEntry(k, '$v'));

  Future<void> _saveJson(String key, Object value) =>
      _prefs.setString(key, jsonEncode(value));

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
    await _saveJson(_Keys.readingPositions, _reading);
  });

  bool buildingMode = false;
  Future<void> setBuildingMode(bool value) => _mutate(() async {
    if (!await _prefs.setBool(_Keys.buildingMode, value)) {
      throw StateError('无法保存盖楼模式');
    }
    buildingMode = value;
    clearReadingPages();
    notifyListeners();
  });

  String themePreference = 'system';
  int themeColor = _defaultAccentColor;
  int buttonColor = _defaultAccentColor;
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
    if (!await _prefs.setInt(_Keys.buttonColor, value)) {
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
        if (!await _prefs.setInt(_Keys.backgroundColor, value)) {
          throw StateError('无法保存背景颜色');
        }
        if (!await _prefs.setBool(
          _Keys.backgroundFollowsSystem,
          followSystem,
        )) {
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
    if (!await _prefs.setInt(_Keys.themeColor, value)) {
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
        await _saveJson(_Keys.signedForums, _signedForums);
      });

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    // Reply drafts are no longer kept between launches.
    for (final key
        in _prefs
            .getKeys()
            .where((key) => key.startsWith(_Keys.replyDraftPrefix))
            .toList()) {
      await _prefs.remove(key);
    }
    _reading = _readJson(
      _Keys.readingPositions,
      '{}',
      object,
      <String, dynamic>{},
    );
    buildingMode = _prefs.getBool(_Keys.buildingMode) ?? false;
    final theme = _prefs.getString(_Keys.themeMode);
    backgroundFollowsSystem =
        _prefs.getBool(_Keys.backgroundFollowsSystem) ?? false;
    backgroundColor =
        (_prefs.getInt(_Keys.backgroundColor) ??
            (theme == 'dark' ? 0xff181818 : 0xffF7F8FA)) |
        0xff000000;
    themeColor =
        (_prefs.getInt(_Keys.themeColor) ?? _defaultAccentColor) | 0xff000000;
    buttonColor = (_prefs.getInt(_Keys.buttonColor) ?? themeColor) | 0xff000000;
    // Import the old shared color once; later launches must not follow changes
    // to the independently saved accent color.
    if (!_prefs.containsKey(_Keys.buttonColor)) {
      await _prefs.setInt(_Keys.buttonColor, buttonColor);
    }
    themePreference = _themeModes.contains(theme) ? theme! : 'system';
    recent = _prefs.getStringList(_Keys.recentForums) ?? [];
    forumKeywords = _prefs.getStringList(_Keys.forumKeywords) ?? [];
    _signedForums = _readJson(_Keys.signedForums, '{}', _stringMap, {});
    history = _readJson(_Keys.threadHistory, '[]', objects, <Json>[]);
    // The two block lists were historically restored together: if either is
    // unreadable, both start empty.
    try {
      blockedForums = _stringMap(
        jsonDecode(_prefs.getString(_Keys.blockedForums) ?? '{}'),
      );
      blockedUsers = _stringMap(
        jsonDecode(_prefs.getString(_Keys.blockedUsers) ?? '{}'),
      );
    } catch (_) {
      blockedForums = {};
      blockedUsers = {};
    }
  }

  Future<void> visit(String name) => _mutate(() async {
    if (name.trim().isEmpty) return;
    if (recent.isNotEmpty && recent.first == name) return;
    final updated = [name, ...recent.where((n) => n != name)].take(20).toList();
    await _prefs.setStringList(_Keys.recentForums, updated);
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
    if (!_themeModes.contains(mode)) return;
    await _prefs.setString(_Keys.themeMode, mode);
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
        await _saveJson(_Keys.threadHistory, updated);
        history = updated;
        notifyListeners();
      });

  Future<void> clearHistory() => _mutate(() async {
    clearReadingPages();
    await _prefs.remove(_Keys.threadHistory);
    await _prefs.remove(_Keys.recentForums);
    await _prefs.remove(_Keys.readingPositions);
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
    await _prefs.setStringList(_Keys.forumKeywords, updated);
    forumKeywords = updated;
    notifyListeners();
  });

  Future<void> removeForumKeyword(String word) => _mutate(() async {
    final updated = forumKeywords.where((v) => v != word).toList();
    await _prefs.setStringList(_Keys.forumKeywords, updated);
    forumKeywords = updated;
    notifyListeners();
  });

  Future<void> blockForum(String name) => _mutate(() async {
    final updated = Map<String, String>.of(blockedForums)
      ..remove(name.toLowerCase());
    updated[name.toLowerCase()] = name;
    await _saveJson(_Keys.blockedForums, updated);
    blockedForums = updated;
    notifyListeners();
  });

  Future<void> blockUser(String key, String name) => _mutate(() async {
    if (key.isEmpty) return;
    final updated = Map<String, String>.of(blockedUsers)..remove(key);
    updated[key] = name;
    await _saveJson(_Keys.blockedUsers, updated);
    blockedUsers = updated;
    notifyListeners();
  });

  Future<void> unblock(String key, {required bool forum}) => _mutate(() async {
    final updated = Map<String, String>.of(forum ? blockedForums : blockedUsers)
      ..remove(key);
    await _saveJson(forum ? _Keys.blockedForums : _Keys.blockedUsers, updated);
    if (forum) {
      blockedForums = updated;
    } else {
      blockedUsers = updated;
    }
    notifyListeners();
  });
}
