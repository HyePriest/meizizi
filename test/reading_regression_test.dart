import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'hot list renders before floor lookup and receives the real floor later',
    () async {
      final lookup = Completer<http.Response>();
      final updated = Completer<Map<String, int>>();
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.queryParameters['cmd'] == '302001') {
            return http.Response.bytes([
              18,
              10,
              50,
              5,
              8,
              137,
              6,
              24,
              0,
              144,
              3,
              2,
            ], 200);
          }
          if (request.bodyFields.containsKey('pid')) return lookup.future;
          return http.Response(
            '{"error_code":0,"post_list":[{"id":100,"floor":1}]}',
            200,
          );
        }),
      );
      try {
        final result = await api.thread(
          '9',
          1,
          hot: true,
          onFloorNumbers: updated.complete,
        );
        expect(result.posts.last['floor_pending'], isTrue);
        expect(lookup.isCompleted, isFalse);
        lookup.complete(
          http.Response(
            '{"error_code":0,"post_list":[{"id":777,"floor":42}]}',
            200,
          ),
        );
        expect((await updated.future)['777'], 42);
      } finally {
        api.close();
      }
    },
  );

  test(
    'floor reads are bounded and neighboring floors prevent further lookups',
    () async {
      var active = 0, maximum = 0, lookups = 0;
      final data = <int>[
        for (var id = 700; id < 707; id++) ...[
          50,
          5,
          8,
          (id & 127) | 128,
          id >> 7,
          24,
          0,
        ],
        144,
        3,
        2,
      ];
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.queryParameters['cmd'] == '302001') {
            return http.Response.bytes([18, data.length, ...data], 200);
          }
          if (!request.bodyFields.containsKey('pid')) {
            return http.Response(
              '{"error_code":0,"post_list":[{"id":100,"floor":1}]}',
              200,
            );
          }
          lookups++;
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          return http.Response(
            jsonEncode({
              'error_code': 0,
              'post_list': [
                for (var id = 700; id < 707; id++)
                  {'id': id, 'floor': id - 660},
              ],
            }),
            200,
          );
        }),
      );
      try {
        final result = await api.thread('9', 1, hot: true);
        expect(maximum, 4);
        expect(lookups, 4);
        expect(result.posts.last['floor'], 46);
        await api.thread('9', 1, hot: true);
        expect(lookups, 4);
      } finally {
        api.close();
      }
    },
  );
  test(
    'hot comments retain their original floor through post-ID lookup',
    () async {
      final lookups = <String>[];
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.queryParameters['cmd'] == '302001') {
            // PbPage response: post 777, omitted/zero floor, hot sort type 2.
            return http.Response.bytes([
              18,
              10,
              50,
              5,
              8,
              137,
              6,
              24,
              0,
              144,
              3,
              2,
            ], 200);
          }
          final pid = request.bodyFields['pid'];
          if (pid != null) lookups.add(pid);
          return http.Response(
            jsonEncode({
              'error_code': 0,
              'forum': {'id': 3, 'name': '测试'},
              'thread': {
                'id': 9,
                'agree': {'agree_num': 50},
              },
              'post_list': [
                pid == null
                    ? {'id': 100, 'floor': 1}
                    : {'id': 777, 'floor': 42},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      try {
        final result = await api.thread('9', 1, hot: true);
        expect(result.posts.map((p) => p['floor']), [1, 42]);
        expect(lookups, ['777']);
        expect(object(result.data['thread'])['agree'], {'agree_num': 50});
      } finally {
        api.close();
      }
    },
  );
  test(
    'latest reply and publish use their respective server sort values',
    () async {
      final sorts = <String?>[];
      final api = TiebaApi(
        client: MockClient((request) async {
          sorts.add(request.bodyFields['sort_type']);
          return http.Response('{"error_code":0}', 200);
        }),
      );
      try {
        await api.forum('测试', 1);
        await api.forum('测试', 1, category: '最新发布');
        expect(sorts, ['0', '1']);
      } finally {
        api.close();
      }
    },
  );
  test('floor HTML images and structured inline HTML become image parts', () {
    final parts = contentParts(
      '文字<br><img class="BDE_Image" src="//example.com/pic.jpg">',
    );
    expect(parts.last['type'], 3);
    expect(httpsImage(parts.last['src']), 'https://example.com/pic.jpg');
    expect(
      contentParts([
        {'type': 0, 'text': '<img src="https://example.com/pic.jpg">'},
      ]).single['type'],
      3,
    );
  });
  test('relative labels use last reply time rather than publication time', () {
    final now = DateTime.now();
    expect(
      relativeDate(
        now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch,
        now: now,
      ),
      '3分钟前',
    );
    expect(
      threadTimeLabel({
        'create_time': 100,
        'last_time_int': now
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      }, latestReply: true),
      '最近回复 2小时前',
    );
    expect(
      threadTimeLabel({'create_time': 100}, latestReply: true),
      '最近回复时间未知',
    );
  });
  test('keyword matching targets forum names and survives restoring', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore.instance;
    await store.restore();
    await store.addForumKeyword('大学');
    await store.restore();
    expect(store.hidden({'fname': '北京大学', 'title': '公告'}, {}), isTrue);
    expect(store.hidden({'fname': '游戏', 'title': '大学毕业'}, {}), isFalse);
    await store.removeForumKeyword('大学');
    expect(store.hidden({'fname': '北京大学'}, {}), isFalse);
  });
  test('history keeps latest visit first, deduplicates and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore.instance;
    await store.restore();
    await store.visitThread('1', '第一帖', '测试');
    await store.visitThread('2', '第二帖', '测试');
    await store.visitThread('1', '第一帖新标题', '测试');
    await store.restore();
    expect(store.history.map((p) => p['id']), ['1', '2']);
    expect(store.history.first['title'], '第一帖新标题');
  });
  test(
    'thumbnail extraction keeps photos and excludes emoticons and videos',
    () {
      final images = threadImages({
        'media': [
          {
            'type': '3',
            'small_pic': 'https://example.com/p.jpg',
            'origin_pic': 'https://example.com/p-original.jpg',
          },
          {'type': 'video', 'src': 'https://example.com/v.mp4'},
        ],
      });
      expect(images.length, 1);
      expect(images.single['original'], 'https://example.com/p-original.jpg');
    },
  );
}
