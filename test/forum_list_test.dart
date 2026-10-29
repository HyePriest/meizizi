import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/features/reading/reading_controller.dart';
import 'package:tieba/pages/reading_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'parse error offers retry and genuine empty result has an empty label',
    (tester) async {
      await LocalStore.instance.restore();
      var broken = true;
      final api = TiebaApi(
        client: MockClient(
          (_) async => http.Response(
            broken ? '{"error_code":0,"page_data":{"future_list":[]}}' : '{"error_code":0,"thread_list":[],"forum":{"name":"图拉丁"},"page":{"has_more":0}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '图拉丁', api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('帖子列表解析失败'), findsOneWidget);
      expect(find.text('当前分类暂无帖子'), findsNothing);
      expect(find.text('加载下一页'), findsNothing);
      broken = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('当前分类暂无帖子'), findsOneWidget);
      expect(find.textContaining('帖子列表解析失败'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 31));
    },
  );
  test(
    'forum requests classic lists and retains pinned posts and pagination',
    () async {
      final api = TiebaApi(
        client: MockClient((request) async {
          expect(request.url.path, '/c/f/frs/page');
          expect(request.bodyFields['kw'], '图拉丁');
          // Mirrors the observed server switch: 22.12 returns page_data only.
          final classic = request.bodyFields['_client_version'] == '12.35.1.0';
          final page = int.parse(request.bodyFields['pn']!);
          return http.Response(
            jsonEncode({
              'error_code': 0,
              'forum': {'name': '图拉丁'},
              'page': {'current_page': page, 'has_more': page == 1 ? 1 : 0},
              if (classic)
                'thread_list': [
                  if (page == 1) {'tid': 100, 'is_top': 1, 'title': '置顶帖'},
                  {'tid': 100 + page, 'title': '普通帖$page'},
                ]
              else
                'page_data': {
                  'feed_list': [
                    {'layout': 'feed'},
                  ],
                },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final reader = ReadingController(api);
      try {
        const query = ReadingQuery(forum: '图拉丁');
        await reader.load(query, reset: true);
        expect(reader.error, isNull);
        expect(reader.data.pinned.single['id'], '100');
        expect(reader.data.items.single['id'], '101');
        expect(reader.data.hasMore, isTrue);
        await reader.load(query);
        expect(reader.data.items.map((item) => item['id']), ['101', '102']);
        expect(reader.data.pinned.length, 1);
        expect(reader.data.page, 2);
        expect(reader.data.hasMore, isFalse);
      } finally {
        reader.dispose();
        api.close();
      }
    },
  );

  test('forum categories retain their request parameters', () async {
    final requests = <Map<String, String>>[];
    final api = TiebaApi(
      client: MockClient((request) async {
        requests.add(request.bodyFields);
        return http.Response('{"error_code":0,"thread_list":[]}', 200);
      }),
    );
    try {
      for (final category in ['最新回复', '最新发布', '热门', '精华']) {
        await api.forum('图拉丁', 2, category: category);
      }
      expect(requests.map((p) => p['sort_type']), ['0', '1', '3', '0']);
      expect(requests.every((p) => p['pn'] == '2' && p['rn'] == '20'), isTrue);
      expect(requests.take(3).every((p) => !p.containsKey('is_good')), isTrue);
      expect(requests.last['is_good'], '1');
      expect(requests.last['cid'], '0');
    } finally {
      api.close();
    }
  });

  test(
    'card responses reach the reader through the real API adapter',
    () async {
      final api = TiebaApi(
        client: MockClient(
          (_) async => http.Response(
            File('test/fixtures/forum_cards.json').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final reader = ReadingController(api);
      try {
        await reader.load(const ReadingQuery(forum: '图拉丁'), reset: true);
        expect(reader.error, isNull);
        expect(reader.data.items.length, 2);
        expect(reader.data.pinned.length, 2);
        expect(reader.data.hasMore, isTrue);
      } finally {
        reader.dispose();
        api.close();
      }
    },
  );

  test(
    'parse failure is visible and retry keeps previously loaded posts',
    () async {
      var broken = false;
      final api = TiebaApi(
        client: MockClient(
          (_) async => http.Response(
            broken ? '{"error_code":0,"page_data":{"new_format":[]}}' : '{"error_code":0,"thread_list":[{"id":123,"title":"正常帖子"}],"page":{"has_more":1}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final reader = ReadingController(api);
      try {
        const query = ReadingQuery(forum: '图拉丁');
        await reader.load(query, reset: true);
        broken = true;
        await reader.load(query);
        expect(reader.error, contains('帖子列表解析失败'));
        expect(reader.data.items.single['id'], '123');
        expect(reader.data.page, 1);
        broken = false;
        await reader.load(query);
        expect(reader.error, isNull);
        expect(reader.data.page, 2);
      } finally {
        reader.dispose();
        api.close();
      }
    },
  );
}
