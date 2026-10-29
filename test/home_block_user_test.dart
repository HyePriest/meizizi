import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/home/home_controller.dart';
import 'package:tieba/widgets/home_thread_card.dart';

Json thread(String id, String uid, String name) => {
  'id': id,
  'title': '帖子$id',
  'forum_name': '测试',
  'forum_info': {'member_num': 1, 'thread_num': 2},
  'author': {'id': uid, 'name_show': name},
};

Widget card(Json item, {ValueChanged<String>? onBlock}) {
  final user = object(item['author']);
  return HomeThreadCard(
    thread: item,
    user: user,
    onOpenForum: () {},
    onOpen: () {},
    onShare: () async {},
    onBlock:
        onBlock ??
        (choice) {
          if (choice == 'forum') {
            LocalStore.instance.blockForum(threadForumName(item));
          } else {
            LocalStore.instance.blockUser(userKey(user, item), author(user));
          }
        },
  );
}

Future<void> finishSelection(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
  });

  testWidgets(
    'home uses the current author nickname and persists only that user ID',
    (tester) async {
      // Observed endpoint behavior: 8.0.8.0 returns the old account name;
      // 22.12.1.0 and the thread details return the current display nickname.
      final api = TiebaApi(
        client: MockClient((request) async {
          expect(request.url.path, '/c/f/excellent/personalized');
          expect(request.bodyFields['pn'], '1');
          final legacy = request.bodyFields['_client_version'] == '8.0.8.0';
          return http.Response(
            jsonEncode({
              'error_code': 0,
              'has_more': 0,
              'thread_list': [
                thread('101', '6840538034', legacy ? '旧账号名' : '当前昵称'),
                thread('102', '88', '当前昵称'),
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final feed = HomeController(api: api);
      addTearDown(feed.dispose);
      await feed.load(reset: true);
      final store = LocalStore.instance;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: store,
              builder: (_, _) => ListView(
                children: [
                  for (final item in feed.state.items)
                    if (!store.hidden(item, object(item['author']))) card(item),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('屏蔽内容').first);
      await tester.pumpAndSettle();
      expect(find.text('屏蔽 当前昵称'), findsOneWidget);
      expect(find.text('屏蔽 旧账号名'), findsNothing);
      await tester.tap(find.text('屏蔽 当前昵称'));
      await finishSelection(tester);
      expect(store.blockedUsers, {'id:6840538034': '当前昵称'});
      expect(find.text('帖子101'), findsNothing);
      expect(find.text('帖子102'), findsOneWidget);

      await store.restore();
      expect(store.userBlocked({'id': '6840538034'}), isTrue);
      expect(store.userBlocked({'id': '88', 'name_show': '当前昵称'}), isFalse);
      await store.unblock('id:6840538034', forum: false);
      await tester.pumpAndSettle();
      expect(find.text('帖子101'), findsOneWidget);
      expect(find.text('帖子102'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );

  testWidgets('an open user menu retains its target when the card changes', (
    tester,
  ) async {
    final source = ValueNotifier(thread('101', '11', '打开菜单时的作者'));
    Json? selected;
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<Json>(
            valueListenable: source,
            builder: (_, item, _) => card(
              item,
              onBlock: (choice) {
                expect(choice, 'user');
                selected = item;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('屏蔽内容'));
    await tester.pumpAndSettle();
    source.value = thread('102', '22', '更新后的作者');
    await tester.pump();
    expect(find.text('屏蔽 打开菜单时的作者'), findsOneWidget);
    await tester.tap(find.text('屏蔽 打开菜单时的作者'));
    await finishSelection(tester);
    expect(selected?['id'], '101');
    expect(object(selected?['author']), {'id': '11', 'name_show': '打开菜单时的作者'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('an open forum menu also retains its displayed target', (
    tester,
  ) async {
    final source = ValueNotifier(thread('101', '11', '作者'));
    Json? selected;
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<Json>(
            valueListenable: source,
            builder: (_, item, _) => card(
              item,
              onBlock: (choice) {
                expect(choice, 'forum');
                selected = item;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('屏蔽内容'));
    await tester.pumpAndSettle();
    source.value = {...thread('102', '22', '另一个作者'), 'forum_name': '另一个'};
    await tester.pump();
    await tester.tap(find.text('屏蔽 测试吧'));
    await finishSelection(tester);
    expect(selected?['id'], '101');
    expect(threadForumName(selected ?? {}), '测试');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
