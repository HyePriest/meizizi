import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

// Anonymous, read-only inspection; never submits votes or loads account data.
Future<void> main(List<String> args) async {
  final isThread = args.isNotEmpty && int.tryParse(args.first) != null;
  final body = <String, String>{
    '_client_type': '2',
    '_client_version': '22.12.1.0',
    if (isThread)
      'kz': args.first
    else
      'kw': args.isEmpty ? '原神内容讨论' : args.first,
    'pn': args.length > 1 ? args[1] : '1',
    'rn': '50',
    if (isThread) ...{
      'with_floor': '1',
      'floor_rn': '4',
      'floor_sort_type': '1',
    },
  };
  final keys = body.keys.toList()..sort();
  body['sign'] = md5
      .convert(
        utf8.encode('${keys.map((k) => '$k=${body[k]}').join()}tiebaclient!!!'),
      )
      .toString();
  final client = http.Client();
  try {
    final response = await client.post(
      Uri.https(
        'c.tieba.baidu.com',
        isThread ? '/c/f/pb/page' : '/c/f/frs/page',
      ),
      body: body,
    );
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    stdout.writeln('HTTP ${response.statusCode}, error ${data['error_code']}');
    if (isThread) {
      final thread = data['thread'] as Map? ?? {};
      stdout.writeln(
        jsonEncode({
          'id': thread['id'],
          'poll_info': thread['poll_info'],
          'video_info': thread['video_info'],
        }),
      );
      for (final post in data['post_list'] as List? ?? []) {
        stdout.writeln(
          jsonEncode({
            'id': post['id'],
            'floor': post['floor'],
            'content': post['content'],
            'video_info': post['video_info'],
            'sub_post_number': post['sub_post_number'],
            'sub_post_list': post['sub_post_list'],
          }),
        );
      }
    } else {
      for (final thread in data['thread_list'] as List? ?? []) {
        if (thread['is_vote'] == 1 ||
            thread['video_info'] != null ||
            (args.length > 2 && '${thread['title']}'.contains(args[2]))) {
          stdout.writeln(
            jsonEncode({
              'id': thread['id'],
              'title': thread['title'],
              'is_vote': thread['is_vote'],
              'video_info': thread['video_info'],
            }),
          );
        }
      }
    }
  } finally {
    client.close();
  }
}
