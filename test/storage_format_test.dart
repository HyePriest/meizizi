import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/serial_tasks.dart';
import 'package:tieba/data/time_labels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings saved by earlier versions are restored unchanged', () async {
    SharedPreferences.setMockInitialValues({
      'reply_draft_123': 'old draft',
      'building_mode': true,
      'theme_mode': 'dark',
      'theme_color': 0x00112233,
      'background_follows_system': true,
      'recent_forums': ['a', 'b'],
      'forum_keywords': ['kw'],
      'signed_forums': jsonEncode({'u:a': '2026-1-2'}),
      'thread_history': jsonEncode([
        {'id': '1', 'title': 't'},
      ]),
      'blocked_forums': jsonEncode({'x': 'X'}),
      'blocked_users': jsonEncode({'id:1': 'n'}),
      'reading_positions': jsonEncode({
        '9:': {'floor': 3},
      }),
    });
    final store = LocalStore.instance;
    await store.restore();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.containsKey('reply_draft_123'), isFalse);
    expect(store.buildingMode, isTrue);
    expect(store.themePreference, 'dark');
    expect(store.backgroundColor, 0xff181818);
    expect(store.backgroundFollowsSystem, isTrue);
    expect(store.themeColor, 0xff112233);
    expect(store.buttonColor, 0xff112233);
    expect(prefs.getInt('button_color'), 0xff112233);
    expect(store.recent, ['a', 'b']);
    expect(store.forumKeywords, ['kw']);
    expect(store.forumSigned('u', 'A', now: DateTime(2026, 1, 2)), isTrue);
    expect(store.history.single['title'], 't');
    expect(store.blockedForums, {'x': 'X'});
    expect(store.blockedUsers, {'id:1': 'n'});
    expect(store.readingPosition('9'), {'floor': 3});

    await store.blockUser('id:2', 'm');
    await store.visitThread('5', 'title', 'forum');
    expect(jsonDecode(prefs.getString('blocked_users')!), {
      'id:1': 'n',
      'id:2': 'm',
    });
    expect(
      (jsonDecode(prefs.getString('thread_history')!) as List).first['id'],
      '5',
    );
  });

  test('unreadable saved values fall back to empty data', () async {
    SharedPreferences.setMockInitialValues({
      'thread_history': 'not json',
      'blocked_forums': '{}',
      'blocked_users': 'broken',
    });
    final store = LocalStore.instance;
    await store.restore();
    expect(store.history, isEmpty);
    // Both block lists are reset together, as before.
    expect(store.blockedForums, isEmpty);
    expect(store.blockedUsers, isEmpty);
  });

  test('serial tasks run in order and survive failures', () async {
    final tasks = SerialTasks();
    final log = <String>[];
    final gate = Completer<void>();
    final first = tasks.run(() async {
      await gate.future;
      log.add('first');
      throw StateError('boom');
    });
    final second = tasks.run(() async => log.add('second'));
    gate.complete();
    await expectLater(first, throwsStateError);
    await second;
    expect(log, ['first', 'second']);
  });

  test('timestamps in seconds and milliseconds give the same label', () {
    final now = DateTime(2026, 5, 10, 12);
    final earlier = now.subtract(const Duration(hours: 3));
    final seconds = earlier.millisecondsSinceEpoch ~/ 1000;
    expect(relativeDate(seconds, now: now), '3小时前');
    expect(relativeDate(seconds * 1000, now: now), '3小时前');
    expect(fullDate(0), '时间未知');
  });
}
