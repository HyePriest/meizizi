import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tieba/data/models.dart';
import 'package:tieba/data/post_protocol.dart';

Future<void> main(List<String> args) async {
  final tid = args.isEmpty ? "8923324838" : args.first;
  final client = http.Client();
  Future<Json> read(
    String path,
    String cmd,
    List<int> bytes,
    Json Function(dynamic) decode,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('c.tieba.baidu.com', path, {'cmd': cmd}),
          )
          ..headers['User-Agent'] =
              'bdtb for Android ${cmd == '302002' ? '22.12.1.0' : '12.64.1.1'}'
          ..headers['x_bd_data_type'] = 'protobuf'
          ..files.add(
            http.MultipartFile.fromBytes('data', bytes, filename: 'file'),
          );
    final res = await http.Response.fromStream(await client.send(request));
    final data = decode(res.bodyBytes);
    stdout.writeln('HTTP ${res.statusCode}, error ${object(data['error'])}');
    return object(data['data']);
  }

  try {
    final data = await read(
      '/c/f/pb/page',
      '302001',
      encodeHotPosts(tid, 1, bduss: '', stoken: '', cuid: ''),
      (b) => decodePostResponse(b),
    );
    final posts = objects(data['post_list']);
    stdout.writeln(
      'Posts ${posts.length}, IP fields ${posts.where((p) => firstText([object(p['author'])['ip_address']]).isNotEmpty).length}',
    );
    final parent = args.length > 1 && number(args[1]) > 100000
        ? <String, dynamic>{'id': args[1]}
        : posts.firstWhere(
            (p) => args.length > 1
                ? number(p['floor']) == int.parse(args[1])
                : number(p['sub_post_number']) > 0,
          );
    final floor = await read(
      '/c/f/pb/floor',
      '302002',
      encodeFloor(tid, '${parent['id']}', 1, bduss: '', stoken: '', cuid: ''),
      (b) => decodeFloorResponse(b),
    );
    final replies = objects(floor['subpost_list']);
    stdout.writeln(
      'Replies ${replies.length}, parts ${replies.expand((p) => contentParts(p['content'])).map((p) => p['type']).toSet()}',
    );
    for (final reply in replies) {
      if (contentParts(reply['content'])
          .any((p) => '${p['text']}'.contains('图片'))) {
        stdout.writeln(reply['content']);
      }
      for (final part in contentParts(reply['content'])) {
        if ([3, 20].contains(number(part['type']))) {
          final url = httpsImage(part['cdn_src']);
          final response = await client.get(
            Uri.parse(url),
            headers: {'Referer': 'https://tieba.baidu.com/'},
          );
          stdout.writeln(
            'Image type ${part['type']}, HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes, ${response.headers['content-type']}',
          );
          if (response.statusCode != 200 ||
              !(response.headers['content-type'] ?? '').startsWith('image/')) {
            throw StateError('Image did not load');
          }
        }
      }
    }
    if (replies.isEmpty) throw StateError('No replies received');
  } finally {
    client.close();
  }
}
