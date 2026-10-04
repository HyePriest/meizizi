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
  Future<void> restore() async {
    _prefs = await SharedPreferences.getInstance();
    recent = _prefs.getStringList('recent_forums') ?? [];
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
      blockedUsers.containsKey(userKey(user, thread));
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
