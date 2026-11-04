import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/forum_search_page.dart';
import 'package:tieba/widgets/forum_thread_card.dart';
import 'package:tieba/widgets/thread_thumbnails.dart';

http.Response response(Json data) => http.Response(
  jsonEncode({'error_code': 0, ...data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'search supplements counts, author and first-floor images from details',
    (tester) async {
      final details = Completer<http.Response>();
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('searchpost')) {
            return response({
              'post_list': [
                {
                  'tid': '123',
                  'title': '装机',
                  'content': '搜索摘要',
                  'author': {'name': '作者'},
                },
              ],
              'page': {'has_more': 0},
            });
          }
          expect(request.url.path, '/c/f/pb/page');
          expect(request.bodyFields['kz'], '123');
          expect(request.bodyFields['rn'], '2');
          return details.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ForumSearchPage(name: '图拉丁', api: api),
        ),
      );
      await tester.enterText(find.byType(TextField), '装机');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
      details.complete(
        response({
          'thread': {
            'id': '123',
            'author_id': '9',
            'reply_num': 57,
            'agree': {'agree_num': 132, 'has_agree': 0},
          },
          'user_list': [
            {
              'id': '9',
              'name': '作者',
              'portrait': 'test-portrait',
              'level_id': 6,
            },
          ],
          'post_list': [
            {
              'id': '456',
              'floor': 1,
              'author': {'id': '9'},
              'content': [
                {'type': 0, 'text': '首楼正文'},
                {'type': 3, 'src': 'https://example.com/first.jpg'},
                {'type': 3, 'src': 'https://example.com/second.jpg'},
              ],
            },
            {
              'id': '457',
              'floor': 2,
              'content': [
                {'type': 3, 'src': 'https://example.com/reply.jpg'},
              ],
            },
          ],
        }),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('57'), findsOneWidget);
      expect(find.text('132'), findsOneWidget);
      final card = tester.widget<ForumThreadCard>(find.byType(ForumThreadCard));
      expect(card.user['portrait'], 'test-portrait');
      expect(card.user['level_id'], 6);
      expect(card.thread['abstract'], isNotEmpty);
      expect(threadImages(card.thread).map((image) => image['thumbnail']), [
        'https://example.com/first.jpg',
        'https://example.com/second.jpg',
      ]);
      expect(find.byType(ThreadThumbnails), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  test(
    'absent detail counters remain unknown; real zeros are retained',
    () async {
      var requestIndex = 0;
      final api = TiebaApi(
        client: MockClient(
          (_) async => response({
            'thread': requestIndex++ == 0
                ? <String, dynamic>{}
                : {
                    'reply_num': 0,
                    'agree': {'agree_num': 0},
                  },
          }),
        ),
      );
      final missing = await api.threadFeedDetails('123');
      expect(missing.containsKey('reply_num'), isFalse);
      expect(missing.containsKey('agree'), isFalse);
      final zero = await api.threadFeedDetails('123');
      expect(zero['reply_num'], 0);
      expect(object(zero['agree'])['agree_num'], 0);
      api.close();
    },
  );
}
