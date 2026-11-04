import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/reading/reading_controller.dart';
import 'package:tieba/pages/reading_page.dart';

const section = ForumSection(id: 44425, name: '装机求助', type: 15);
final navigation = {
  'tab': [
    {'tab_id': 1, 'tab_name': '热门', 'tab_type': 13},
    {'tab_id': 44425, 'tab_name': '装机求助', 'tab_type': 15},
    {'tab_id': 3713719, 'tab_name': '小白求助贴', 'tab_type': 15},
    {'tab_id': 507, 'tab_name': '合辑', 'tab_type': 102},
  ],
};

http.Response response(Json data) => http.Response(
  jsonEncode({'error_code': 0, ...data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sections come from forum navigation and exclude special destinations',
    () {
      expect(
        forumSections({'nav_tab_info': navigation}).map((tab) => tab.name),
        ['装机求助', '小白求助贴'],
      );
      expect(forumSections({}), isEmpty);
    },
  );

  test('section switching preserves forum and navigation and paginates the section', () async {
    final requests = <http.Request>[];
    final api = TiebaApi(
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/generalTabList')) {
          final page = int.parse(request.bodyFields['pn']!);
          return response({
            'general_list': [
              {'tid': 200 + page, 'title': '板块帖$page'},
            ],
            'has_more': page == 1 ? 1 : 0,
          });
        }
        return response({
          'forum': {'id': 74075, 'name': '图拉丁', 'member_num': 8251047},
          'nav_tab_info': navigation,
          'thread_list': [
            {'tid': 100, 'title': '全吧帖'},
          ],
          'page': {'has_more': 0},
        });
      }),
    );
    final reader = ReadingController(api);
    try {
      await reader.load(const ReadingQuery(forum: '图拉丁'), reset: true);
      reader.clearItems();
      const query = ReadingQuery(
        forum: '图拉丁',
        category: '装机求助',
        section: section,
      );
      await reader.load(query, reset: true);
      expect(reader.error, isNull);
      expect(reader.data.forum['member_num'], 8251047);
      expect(forumSections(reader.data.result!.data).length, 2);
      expect(reader.data.items.single['id'], '201');
      expect(reader.data.hasMore, isTrue);
      await reader.load(query);
      expect(reader.data.items.map((post) => post['id']), ['201', '202']);
      expect(reader.data.hasMore, isFalse);
      expect(requests.last.bodyFields['tab_id'], '44425');
      expect(requests.last.bodyFields['forum_id'], '74075');
      expect(requests.last.bodyFields['last_thread_id'], '201');
      expect(requests.last.bodyFields['pn'], '2');
      await reader.load(
        const ReadingQuery(forum: '图拉丁', category: '精华'),
        reset: true,
      );
      expect(requests.last.url.path, '/c/f/frs/page');
      expect(requests.last.bodyFields['is_good'], '1');
      expect(requests.last.bodyFields.containsKey('tab_id'), isFalse);
      expect(reader.data.items.single['id'], '100');
    } finally {
      reader.dispose();
      api.close();
    }
  });

  testWidgets(
    'category bar stays visible after scrolling and scrolls sideways',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await LocalStore.instance.restore();
      final requests = <http.Request>[];
      final api = TiebaApi(
        client: MockClient((request) async {
          requests.add(request);
          return response({
            'forum': {
              'name': '图拉丁',
              'avatar': 'https://example.com/avatar.png',
            },
            'nav_tab_info': navigation,
            'thread_list': [
              for (var i = 0; i < 20; i++)
                {'tid': 100 + i, 'title': '帖子$i', 'abstract': '帖子内容'},
            ],
            'page': {'has_more': 0},
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '图拉丁', api: api),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests.first.bodyFields['sort_type'], '3');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '热门'))
            .selected,
        isTrue,
      );
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.take(4).map((chip) => (chip.label as Text).data), [
        '精华',
        '热门',
        '最新回复',
        '最新发布',
      ]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('精华').hitTestable(), findsOneWidget);
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      await tester.drag(horizontal, const Offset(-600, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('小白求助贴').hitTestable(), findsOneWidget);
      final horizontalWidget = tester.widget<SingleChildScrollView>(horizontal);
      expect(horizontalWidget.controller!.offset, greaterThan(0));
      await tester.drag(find.byType(CustomScrollView), const Offset(-260, 0));
      await tester.pump(const Duration(seconds: 1));
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '最新回复'))
            .selected,
        isTrue,
      );
      expect(find.text('最新回复').hitTestable(), findsOneWidget);
      expect(
        requests
            .where((request) => request.url.path == '/c/f/frs/page')
            .last
            .bodyFields['sort_type'],
        '0',
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(260, 0));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '热门'))
            .selected,
        isTrue,
      );
      expect(find.text('热门').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );
}
