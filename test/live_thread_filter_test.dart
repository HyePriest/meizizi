import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/forum_protocol.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/home/home_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('thread lists filter live cards and retain ordinary posts', () {
    final page = TiebaPage({
      'thread_list': [
        {'id': '1', 'is_livepost': '1'},
        {
          'id': '2',
          'ala_info': {'live_id': '123'},
        },
        {
          'id': '3',
          'live_info': {'live_id': '456'},
        },
        {'id': '4', 'live_id': '789'},
        {
          'id': '5',
          'livecard_info': {'room_id': '123'},
        },
        {'id': '6', 'is_live': true},
        {'id': '7', 'title': '讨论直播', 'thread_type': 40},
        {
          'id': '8',
          'author': {
            'ala_info': {'live_status': 1},
          },
        },
        {'id': '9', 'is_livepost': 0, 'ala_info': {}, 'live_id': '0'},
        {'id': '10', 'title': '没有吧名的普通帖子'},
      ],
    });
    expect(page.threads.map((t) => t['id']), ['7', '8', '9', '10']);
  });

  test('intentionally filtered forum pages are not parse failures', () {
    final decoded = decodeForumThreads({
      'thread_list': [
        {'id': '1', 'is_livepost': 1},
      ],
      'page_data': {
        'feed_list': [
          {
            'layout': 'feed',
            'feed': {
              'business_info': [
                {'key': 'is_livepost', 'value': '1'},
              ],
            },
          },
        ],
      },
      'page': {'has_more': 1},
    });
    expect(decoded.threads, isEmpty);
    expect(decoded.issue, isNull);
  });

  test('a live-only home page still permits loading the next page', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    final api = TiebaApi(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error_code': 0,
            'thread_list': [
              if (request.bodyFields['pn'] == '1')
                {
                  'id': '1',
                  'ala_info': {'live_id': '123'},
                }
              else
                {'id': '2', 'title': '普通帖子'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final controller = HomeController(api: api);
    addTearDown(controller.dispose);
    await controller.load(reset: true);
    expect(controller.state.items, isEmpty);
    expect(controller.canLoadMore, isTrue);
    await controller.load();
    expect(controller.state.error, isNull);
    expect(controller.state.items.single['id'], '2');
    expect(controller.state.page, 2);
  });
}
