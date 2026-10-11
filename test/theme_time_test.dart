import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/models.dart';
import 'package:tieba/pages/profile_page.dart';
import 'package:tieba/widgets/post_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('recent hours, current-year dates and past years remain precise', () {
    final now = DateTime(2026, 10, 12, 18, 30);
    int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    expect(
      commentTime(ts(now.subtract(const Duration(seconds: 30))), now: now),
      '刚刚',
    );
    expect(
      commentTime(ts(now.subtract(const Duration(minutes: 35))), now: now),
      '35分钟前',
    );
    expect(
      commentTime(
        ts(now.subtract(const Duration(hours: 5, minutes: 15))),
        now: now,
      ),
      '5小时前',
    );
    expect(
      commentTime(ts(DateTime(2026, 10, 5, 14, 17)), now: now),
      '10-05 14:17',
    );
    expect(
      commentTime(ts(DateTime(2024, 10, 5, 14, 17)), now: now),
      '2024-10-05 14:17',
    );
    expect(commentTime(0, now: now), '时间未知');
  });
  test(
    'theme and blacklist persist, and unblock restores visibility',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore.instance;
      await store.restore();
      expect(store.themePreference, 'system');
      await store.setTheme('dark');
      await store.blockUser('id:8', '测试作者');
      await store.restore();
      expect(store.themePreference, 'dark');
      expect(store.userBlocked({'id': 8}), isTrue);
      expect(store.hidden({'author_id': 8}, {}), isTrue);
      await store.setTheme('light');
      await store.unblock('id:8', forum: false);
      await store.restore();
      expect(store.themePreference, 'light');
      expect(store.userBlocked({}, {'author_id': 8}), isFalse);
    },
  );
  testWidgets('settings selects and saves both black and white themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsContent())),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('黑色').last);
    await tester.pumpAndSettle();
    expect(LocalStore.instance.themePreference, 'dark');
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('白色').last);
    await tester.pumpAndSettle();
    expect(LocalStore.instance.themePreference, 'light');
    expect(tester.takeException(), isNull);
  });
  testWidgets('the colored level frame contains the custom name and number', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForumLevelBadge(user: {'level_id': 8}, levelNames: {8: '合体尊者'}),
        ),
      ),
    );
    final frame = tester.getRect(find.byType(Container));
    final name = tester.getRect(find.text('合体尊者'));
    final number = tester.getRect(find.text('8'));
    expect(frame.contains(name.topLeft), isTrue);
    expect(frame.contains(name.bottomRight), isTrue);
    expect(frame.contains(number.center), isTrue);
    expect(tester.takeException(), isNull);
  });
}
