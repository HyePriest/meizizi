import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalStore extends ChangeNotifier {
  LocalStore._();
  static final instance = LocalStore._();
  late SharedPreferences _prefs;
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
    if (objects(page['items']).length > 240) return;
    _readingPages[key] = page;
    while (_readingPages.length > 8 ||
        _readingPages.values.fold<int>(
              0,
              (n, p) => n + (p['items'] as List).length,
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
  }) async {
    final key = '$tid:$parent';
    _reading.remove(key);
    _reading[key] = position;
    while (_reading.length > 200) {
      _reading.remove(_reading.keys.first);
    }
    await _prefs.setString('reading_positions', jsonEncode(_reading));
  }

  String themePreference = 'system';
  Map<String, String> _signedForums = {};
  static String _signDay(DateTime now) => '${now.year}-${now.month}-${now.day}';
  bool forumSigned(String account, String name, {DateTime? now}) =>
      account.isNotEmpty &&
      _signedForums['$account:${name.toLowerCase()}'] ==
          _signDay(now ?? DateTime.now());
  Future<void> markForumSigned(
    String account,
    String name, {
    DateTime? now,
  }) async {
    if (account.isEmpty || name.isEmpty) return;
    _signedForums['$account:${name.toLowerCase()}'] = _signDay(
      now ?? DateTime.now(),
    );
    notifyListeners();
    await _prefs.setString('signed_forums', jsonEncode(_signedForums));
  }

  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      _reading = object(
        jsonDecode(_prefs.getString('reading_positions') ?? '{}'),
      );
    } catch (_) {
      _reading = {};
    }
    final theme = _prefs.getString('theme_mode');
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

  Future<void> visit(String name) async {
    if (name.trim().isEmpty) return;
    final updated = [name, ...recent.where((n) => n != name)].take(20).toList();
    await _prefs.setStringList('recent_forums', updated);
    recent = updated;
    notifyListeners();
  }

  bool hidden(Json thread, Json user) =>
      blockedForums.containsKey(threadForumName(thread).toLowerCase()) ||
      blockedUsers.containsKey(userKey(user, thread)) ||
      forumKeywords.any(
        (word) =>
            threadForumName(thread).toLowerCase().contains(word.toLowerCase()),
      );

  bool userBlocked(Json user, [Json post = const {}]) =>
      blockedUsers.containsKey(userKey(user, post));

  Future<void> setTheme(String mode) async {
    if (!['light', 'dark', 'system'].contains(mode)) return;
    await _prefs.setString('theme_mode', mode);
    themePreference = mode;
    notifyListeners();
  }

  Future<void> visitThread(String id, String title, String forum) async {
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
  }

  Future<void> clearHistory() async {
    clearReadingPages();
    await _prefs.remove('thread_history');
    await _prefs.remove('recent_forums');
    await _prefs.remove('reading_positions');
    _reading = {};
    history = [];
    recent = [];
    notifyListeners();
  }

  Future<void> addForumKeyword(String raw) async {
    final word = raw.trim();
    if (word.isEmpty ||
        forumKeywords.any((v) => v.toLowerCase() == word.toLowerCase())) {
      return;
    }
    final updated = [...forumKeywords, word];
    await _prefs.setStringList('forum_keywords', updated);
    forumKeywords = updated;
    notifyListeners();
  }

  Future<void> removeForumKeyword(String word) async {
    final updated = forumKeywords.where((v) => v != word).toList();
    await _prefs.setStringList('forum_keywords', updated);
    forumKeywords = updated;
    notifyListeners();
  }

  Future<void> blockForum(String name) async {
    final updated = {...blockedForums, name.toLowerCase(): name};
    await _prefs.setString('blocked_forums', jsonEncode(updated));
    blockedForums = updated;
    notifyListeners();
  }

  Future<void> blockUser(String key, String name) async {
    if (key.isEmpty) return;
    final updated = {...blockedUsers, key: name};
    await _prefs.setString('blocked_users', jsonEncode(updated));
    blockedUsers = updated;
    notifyListeners();
  }

  Future<void> unblock(String key, {required bool forum}) async {
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
  }
}
