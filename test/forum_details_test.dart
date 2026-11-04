import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/reading/reading_controller.dart';
import 'package:tieba/pages/forum_details_page.dart';
import 'package:tieba/pages/forum_search_page.dart';
import 'package:tieba/widgets/forum_header_card.dart';

http.Response response(Json data) => http.Response(
  jsonEncode({'error_code': 0, ...data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background uses the dedicated header image and never the theme texture',
    () {
      final forum = {
        'header_image': 'http://tieba-ares.cdn.bcebos.com/header.jpg',
        'theme_color': {
          'day': {'pattern_image': 'http://imgsrc.baidu.com/day.jpg'},
          'night': {'pattern_image': 'https://imgsrc.baidu.com/night.jpg'},
        },
      };
      expect(
        forumCoverUrl(forum),
        'https://tieba-ares.cdn.bcebos.com/header.jpg',
      );
      forum.remove('header_image');
      expect(forumCoverUrl(forum), isEmpty);
      expect(forumCoverUrl({}), isEmpty);
    },
  );

  test('forum search sends the forum and parses pagination; rules retain rich content', () async {
    final requests = <http.Request>[];
    final api = TiebaApi(
      client: MockClient((request) async {
        requests.add(request);
        return response(
          request.url.path.endsWith('searchpost')
              ? {
                  'post_list': [
                    {'tid': '123', 'fname': '图拉丁', 'title': '装机'},
                  ],
                  'page': {'has_more': 1},
                }
              : {
                  'title': '本吧吧规',
                  'rules': [
                    {
                      'title': '第一条',
                      'content': [
                        {'type': 0, 'text': '请文明交流'},
                      ],
                    },
                  ],
                },
        );
      }),
    );
    try {
      final result = await api.searchForum('图拉丁', '装机', 2);
      expect(requests.single.url.path, '/c/s/searchpost');
      expect(requests.single.bodyFields['kw'], '图拉丁');
      expect(requests.single.bodyFields['word'], '装机');
      expect(requests.single.bodyFields['only_thread'], '1');
      expect(requests.single.bodyFields['pn'], '2');
      expect(result.items.single['tid'], '123');
      expect(result.hasMore, isTrue);
      final rules = await api.forumRules('74075');
      expect(requests.last.bodyFields['forum_id'], '74075');
      expect(
        objects(objects(rules['rules']).single['content']).single['text'],
        '请文明交流',
      );
    } finally {
      api.close();
    }
  });

  testWidgets(
    'unfollow needs confirmation; follow is direct and shared state updates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({
        'baidu_accounts': jsonEncode({
          'active': 'test-user',
          'accounts': [
            {
              'id': 'test-user',
              'user': {'id': 'test-user'},
              'cookies': {'BDUSS': 'test-only'},
            },
          ],
        }),
      });
      await AuthStore.instance.restore();
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.path.contains('getBawu'))
            return http.Response.bytes([10, 4, 10, 2, 8, 0], 200);
          return response(
            request.url.path.contains('getLevelInfo')
                ? {
                    'level_info': [
                      {'id': 2, 'name': '奔腾II', 'score': 50},
                      {'id': 3, 'name': '图拉丁C3', 'score': 200},
                    ],
                  }
                : {
                    'title': '本吧吧规',
                    'preface': '欢迎交流',
                    'rules': [
                      {
                        'title': '第一条',
                        'content': [
                          {'type': 0, 'text': '请文明交流'},
                        ],
                      },
                    ],
                  },
          );
        }),
      );
      final reader = ReadingController(api);
      reader.restore({
        'forum': {
          'id': 74075,
          'name': '图拉丁',
          'is_like': 1,
          'avatar': 'https://example.com/a.png',
          'level_id': 2,
          'cur_score': 120,
          'member_num': 8251047,
          'thread_num': 3937102,
          'slogan': '技术与装机交流',
        },
        'data': {},
      });
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ForumDetailsPage(
            name: '图拉丁',
            reader: reader,
            api: api,
            onRefresh: () async {},
            onFollow: (followed) async {
              calls++;
              reader.setFollowed(followed);
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('经验 120 / 200'), findsOneWidget);
      expect(find.textContaining('825.1w'), findsOneWidget);
      await tester.tap(find.text('已关注'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('取消关注？'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('保留关注'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      await tester.tap(find.text('已关注'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('取消关注'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      expect(flag(reader.data.forum['is_like']), isFalse);
      await tester.tap(find.text('关注'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 2);
      expect(flag(reader.data.forum['is_like']), isTrue);
      expect(find.text('取消关注？'), findsNothing);
      await tester.tap(find.text('吧规'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ForumRulePage), findsOneWidget);
      expect(find.text('请文明交流', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
      reader.dispose();
      api.close();
    },
  );

  testWidgets('a late search response cannot overwrite a newer keyword', (
    tester,
  ) async {
    final pending = <String, Completer<http.Response>>{};
    final api = TiebaApi(
      client: MockClient((request) {
        final word = request.bodyFields['word']!;
        return (pending[word] = Completer<http.Response>()).future;
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ForumSearchPage(name: '图拉丁', api: api),
      ),
    );
    await tester.enterText(find.byType(TextField), '旧关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    pending['新关键词']!.complete(
      response({
        'post_list': [
          {'tid': 2, 'title': '新结果'},
        ],
        'page': {'has_more': 0},
      }),
    );
    await tester.pump(const Duration(milliseconds: 100));
    pending['旧关键词']!.complete(
      response({
        'post_list': [
          {'tid': 1, 'title': '旧结果'},
        ],
        'page': {'has_more': 0},
      }),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
