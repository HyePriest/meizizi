import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/forum_protocol.dart';
import 'package:tieba/data/models.dart';

Json fixture() => object(
  jsonDecode(File('test/fixtures/forum_cards.json').readAsStringSync()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('observed card response preserves pinned and ordinary posts', () {
    final decoded = decodeForumThreads(fixture());
    expect(decoded.issue, isNull);
    expect(decoded.threads.length, 4);
    expect(decoded.threads.where((t) => flag(t['is_top'])).length, 2);
    expect(decoded.threads.first['title'], '【农贸】图拉丁吧硬件交流平台友好互换');
    final post = decoded.threads[2];
    expect(post['id'], '11136383532');
    expect(post['reply_num'], 2);
    expect(post['title'], '未来1700针处理器哪个性价比会更好呢？');
    expect(object(post['author'])['name_show'], '猫猫要吃麦当劳');
    expect(number(object(post['author'])['level_id']), 12);
    expect(contentParts(post['abstract']), isNotEmpty);
    expect(threadImages(post), isNotEmpty);
    expect(number(post['create_time']), greaterThan(0));
    expect(post.containsKey('last_reply_time'), isFalse);
  });

  test('mixed responses deduplicate IDs and preserve classic fields', () {
    final data = fixture();
    data['thread_list'] = [
      {'tid': '11136383532', 'title': 'classic', 'last_reply_time': 99},
      {'id': 77, 'title': 'ad', 'is_ad': 1},
    ];
    final result = decodeForumThreads(data);
    expect(result.issue, isNull);
    expect(result.threads.length, 4);
    expect(result.threads.first['title'], 'classic');
    expect(result.threads.first['last_reply_time'], 99);
  });

  test(
    'explicit empty lists differ from missing, damaged and unknown lists',
    () {
      for (final data in [
        <String, dynamic>{'thread_list': []},
        <String, dynamic>{
          'page_data': {'feed_list': []},
        },
      ]) {
        expect(decodeForumThreads(data).issue, isNull);
      }
      for (final data in [
        <String, dynamic>{
          'forum': {'name': 'empty?'},
        },
        <String, dynamic>{'thread_list': {}},
        <String, dynamic>{
          'thread_list': [
            {'title': 'missing ID'},
          ],
        },
        <String, dynamic>{
          'thread_list': [],
          'page': {'has_more': 1},
        },
        <String, dynamic>{
          'page_data': {
            'feed_list': [
              {'layout': 'future_feed'},
            ],
          },
        },
        <String, dynamic>{
          'page_data': {
            'feed_list': [
              {'layout': 'feed', 'feed': {}},
            ],
          },
        },
      ]) {
        expect(decodeForumThreads(data).issue, isNotNull, reason: '$data');
      }
    },
  );

  test('unknown cards retain readable posts and report partial parsing', () {
    final data = fixture();
    (object(data['page_data'])['feed_list'] as List).add({
      'layout': 'future_feed',
    });
    final result = decodeForumThreads(data);
    expect(result.threads.length, 4);
    expect(result.issue, 'unrecognized_thread_cards');
  });
}
