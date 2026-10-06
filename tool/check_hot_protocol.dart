import 'dart:typed_data';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:tieba/data/models.dart';
import 'package:tieba/data/post_protocol.dart';

// Read-only public protocol check. No login credentials or write endpoints.
Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('c.tieba.baidu.com', '/c/f/pb/page', {'cmd': '302001'}),
          )
          ..headers['User-Agent'] = 'bdtb for Android 12.64.1.1'
          ..headers['x_bd_data_type'] = 'protobuf'
          ..files.add(
            http.MultipartFile.fromBytes(
              'data',
              encodeHotPosts(
                args.isEmpty ? '8923324838' : args.first,
                1,
                bduss: '',
                stoken: '',
                cuid: '',
              ),
              filename: 'file',
            ),
          );
    final response = await http.Response.fromStream(await client.send(request));
    final parsed = decodePostResponse(response.bodyBytes);
    final data = object(parsed['data']);
    stdout.writeln(data['pb_sort_info']);
    stdout.writeln(
      'HTTP ${response.statusCode}, error ${object(parsed['error'])}, sort ${data['sort_type']}',
    );
    stdout.writeln(
      objects(data['post_list'])
          .map((p) => '${p['floor']}楼:${object(p['agree'])['agree_num'] ?? 0}赞')
          .join(', '),
    );
    if (response.statusCode != 200 ||
        number(object(parsed['error'])['errorno']) != 0 ||
        objects(data['post_list']).isEmpty) {
      throw StateError('Server did not return native posts');
    }
    stdout.writeln(
      number(data['sort_type']) == 2 ? 'Server confirmed hot sorting' : 'Server offers only floor sorting for this public request; UI must fall back',
    );
    for (final invalid in [
      <int>[0],
      <int>[18, 255],
      <int>[8, 128],
    ]) {
      try {
        decodePostResponse(Uint8List.fromList(invalid));
      } on FormatException {
        continue;
      }
      throw StateError('Malformed protobuf was accepted');
    }
    stdout.writeln('Native response and malformed-response checks passed');
  } finally {
    client.close();
  }
}
