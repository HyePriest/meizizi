import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/reading/reading_controller.dart';
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

  ReadingController readerFor(ForumApi api) =>
      ReadingController(api, initialData: ReadingData(forum: api.forumData));

  test('confirmed unfollow survives stale metadata and feed refresh', () async {
    final api = ForumApi();
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    await reader.changeForumFollowed('状态测试', false);
    await reader.refreshForum('状态测试');
    expect(reader.forumFollowed, false);
    await reader.load(const ReadingQuery(forum: '状态测试'), reset: true);
    expect(reader.forumFollowed, false);
    expect(reader.data.forum['is_liked'], 0);
    api.serverFollowed = false;
    await reader.changeForumFollowed('状态测试', true);
    await reader.refreshForum('状态测试');
    expect(reader.forumFollowed, true);
    expect(api.writes, [false, true]);
  });

  test('authoritative zero normalizes conflicting follow aliases', () {
    final api = ForumApi();
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    reader.updateForum({'is_like': 0, 'is_liked': 1});
    expect(reader.forumFollowed, false);
    expect(reader.data.forum['is_liked'], 0);
    reader.updateForum({'is_liked': 1});
    expect(reader.forumFollowed, true);
    expect(reader.data.forum['is_like'], 1);
    expect(reader.data.forum['id'], 74075);
  });

  test('duplicate clicks and sign/follow overlap are serialized', () async {
    final api = ForumApi();
    final pending = Completer<void>();
    api.write = (_) => pending.future;
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    final write = reader.changeForumFollowed('状态测试', false);
    expect(reader.forumActionsBusy, true);
    expect(await reader.changeForumFollowed('状态测试', false), false);
    expect(api.writes, [false]);
    pending.complete();
    await write;
    reader.setForumSigning(true);
    expect(await reader.changeForumFollowed('状态测试', true), false);
    reader.setForumSigning(false);
    expect(reader.forumActionsBusy, false);
  });

  test('uncertain result needs a fresh explicit follow status', () async {
    final api = ForumApi();
    api.write = (_) async =>
        throw const TiebaException('连接中断', uncertain: true);
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    await expectLater(
      reader.changeForumFollowed('状态测试', false),
      throwsA(isA<TiebaException>()),
    );
    expect(reader.forumFollowUncertain, true);
    expect(await reader.changeForumFollowed('状态测试', false), false);
    api.read = () async => TiebaPage({
      'forum': {'id': 74075},
    });
    await reader.refreshForum('状态测试');
    expect(reader.forumFollowUncertain, true);
    api.read = null;
    api.serverFollowed = false;
    await reader.refreshForum('状态测试');
    expect(reader.forumFollowUncertain, false);
    expect(reader.forumFollowed, false);
    expect(api.writes, [false]);
  });

  test('definite rejection leaves the prior state usable', () async {
    final api = ForumApi();
    api.write = (_) async => throw const TiebaException('操作频繁');
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    await expectLater(
      reader.changeForumFollowed('状态测试', false),
      throwsA(isA<TiebaException>()),
    );
    expect(reader.forumFollowed, true);
    expect(reader.forumActionsBusy, false);
    expect(reader.forumFollowUncertain, false);
  });

  test('old writes and metadata cannot populate a cleared account', () async {
    final api = ForumApi();
    final pending = Completer<void>();
    api.write = (_) => pending.future;
    final reader = readerFor(api);
    addTearDown(reader.dispose);
    addTearDown(api.close);
    final write = reader.changeForumFollowed('状态测试', false);
    reader.clear();
    reader.updateForum({'id': 74075, 'is_like': 1});
    pending.complete();
    expect(await write, false);
    expect(reader.forumFollowed, true);
    final metadata = Completer<TiebaPage>();
    api.read = () => metadata.future;
    final refresh = reader.refreshForum('状态测试');
    reader.clear();
    metadata.complete(
      TiebaPage({
        'forum': {'id': 74075, 'is_like': 1},
      }),
    );
    await refresh;
    expect(reader.data.forum, isEmpty);
    expect(reader.forumActionsBusy, false);
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

  Future<void> unfollow(WidgetTester tester) async {
    await tester.tap(find.text('已关注'));
    await pumpUi(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
    await pumpUi(tester);
  }

  Future<void> cleanup(WidgetTester tester, ForumApi api) async {
    await tester.pumpWidget(const SizedBox());
    await pumpUi(tester);
    await tester.pump(const Duration(seconds: 31));
    api.close();
  }

  testWidgets(
    'unfollow in details updates home; follow on home updates details despite stale reads',
    (tester) async {
      final api = ForumApi();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      expect(find.text('签到'), findsOneWidget);
      await openDetails(tester);
      await unfollow(tester);
      expect(find.text('关注'), findsOneWidget);
      await tester.pageBack();
      await pumpUi(tester);
      expect(find.text('关注'), findsOneWidget);
      expect(find.byType(SignButton), findsNothing);
      api.serverFollowed = false;
      await tester.tap(find.text('关注'));
      await pumpUi(tester);
      expect(find.text('签到'), findsOneWidget);
      await openDetails(tester);
      expect(find.text('已关注'), findsOneWidget);
      expect(api.writes, [false, true]);
      expect(tester.takeException(), isNull);
      await cleanup(tester, api);
    },
  );

  testWidgets(
    'returning during unfollow keeps home disabled and settles to follow',
    (tester) async {
      final api = ForumApi();
      final pending = Completer<void>();
      api.write = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      await openDetails(tester);
      await unfollow(tester);
      expect(find.text('处理中'), findsOneWidget);
      await tester.pageBack();
      await pumpUi(tester);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '签到'),
      );
      expect(button.onPressed, isNull);
      pending.complete();
      await pumpUi(tester);
      expect(find.text('关注'), findsOneWidget);
      expect(api.writes, [false]);
      expect(tester.takeException(), isNull);
      await cleanup(tester, api);
    },
  );

  testWidgets(
    'uncertain unfollow reads server state once and updates both pages without new button labels',
    (tester) async {
      final api = ForumApi();
      api.write = (_) async {
        api.serverFollowed = false;
        throw const TiebaException('连接中断', uncertain: true);
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      await openDetails(tester);
      await unfollow(tester);
      expect(find.text('关注'), findsOneWidget);
      expect(find.text('刷新核对'), findsNothing);
      await tester.pageBack();
      await pumpUi(tester);
      expect(find.text('关注'), findsOneWidget);
      expect(api.writes, [false]);
      await cleanup(tester, api);
    },
  );

  testWidgets(
    'rejected unfollow keeps details followed and home ready to sign',
    (tester) async {
      final api = ForumApi();
      api.write = (_) async => throw const TiebaException('操作频繁，请稍后再试');
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      await openDetails(tester);
      await unfollow(tester);
      expect(find.text('已关注'), findsOneWidget);
      await tester.pageBack();
      await pumpUi(tester);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '签到'))
            .onPressed,
        isNotNull,
      );
      expect(api.writes, [false]);
      await cleanup(tester, api);
    },
  );

  testWidgets(
    'switching account during unfollow ignores the old completion on both pages',
    (tester) async {
      final api = ForumApi();
      final pending = Completer<void>();
      api.write = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '状态测试', api: api),
        ),
      );
      await pumpUi(tester);
      await openDetails(tester);
      await unfollow(tester);
      await tester.runAsync(
        () => AuthStore.instance.save(
          {'BDUSS': 'new-membership-cookie'},
          {'id': 'new-user'},
        ),
      );
      await pumpUi(tester);
      pending.complete();
      await pumpUi(tester);
      expect(find.text('已关注'), findsOneWidget);
      await tester.pageBack();
      await pumpUi(tester);
      expect(find.text('签到'), findsOneWidget);
      expect(api.writes, [false]);
      expect(tester.takeException(), isNull);
      await cleanup(tester, api);
    },
  );
}
