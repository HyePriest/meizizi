import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/forum_details_page.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/forum_header_card.dart';
import 'package:tieba/widgets/forum_widgets.dart';

import 'fixtures/forum_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pumpUi(WidgetTester tester) async {
    await tester.pump();
    // Let preference writes finish outside the widget test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    FlutterSecureStorage.setMockInitialValues({
      'baidu_accounts': jsonEncode({
        'active': 'test-user',
        'accounts': [
          {
            'id': 'test-user',
            'user': {'id': 'test-user'},
            'cookies': {'BDUSS': 'membership-cookie'},
          },
        ],
      }),
    });
    await AuthStore.instance.restore();
  });

  Future<void> openDetails(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ForumHeaderCard),
        matching: find.text('状态测试吧'),
      ),
    );
    await pumpUi(tester);
    expect(find.byType(ForumDetailsPage), findsOneWidget);
  }

  Future<void> cleanup(WidgetTester tester, ForumApi api) async {
    await tester.pumpWidget(const SizedBox());
    await pumpUi(tester);
    await tester.pump(const Duration(seconds: 31));
    api.close();
  }

  testWidgets(
    'sign in flight blocks unfollow in details and success remains signed on return',
    (tester) async {
      final api = ForumApi();
      final pending = Completer<Json>();
      api.sign = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      final signState = tester.state(find.byType(SignButton));
      await tester.tap(find.text('签到'));
      await tester.pump();
      await openDetails(tester);
      expect(find.text('处理中'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '处理中'),
      );
      expect(button.onPressed, isNull);
      expect(signState.mounted, true);
      await tester.runAsync(() async {
        pending.complete({'is_sign_in': 1});
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await pumpUi(tester);
      expect(AuthStore.instance.activeId, 'test-user');
      expect(LocalStore.instance.forumSigned('test-user', '状态测试'), true);
      expect(find.text('已关注'), findsOneWidget);
      await tester.pageBack();
      await pumpUi(tester);
      expect(find.text('已签到'), findsOneWidget);
      expect(api.signs, 1);
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await cleanup(tester, api);
    },
  );
}
