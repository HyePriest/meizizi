import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/tieba_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var identity = 0;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'baidu_accounts': jsonEncode({
        'active': 'test-user',
        'accounts': [
          {
            'id': 'test-user',
            'user': {'id': 'test-user'},
            'cookies': {'BDUSS': 'forum-actions-${++identity}'},
          },
        ],
      }),
    });
    await AuthStore.instance.restore();
  });

  http.Response response(Json data) => http.Response(
    jsonEncode({'error_code': 0, ...data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  TiebaApi apiFor(Json result, List<http.Request> writes) => TiebaApi(
    client: MockClient((request) async {
      if (request.url.path == '/c/s/login') {
        return response({
          'user': {'id': 1},
          'anti': {'tbs': 'test-token'},
        });
      }
      writes.add(request);
      return response(result);
    }),
  );

  test('follow, unfollow and sign use current forum write requests', () async {
    final writes = <http.Request>[];
    final api = apiFor({
      'error': {'errno': 0},
      'user_info': {'is_sign_in': 1},
    }, writes);
    addTearDown(api.close);
    await api.followForum('图拉丁', '74075');
    await api.followForum('图拉丁', '74075', undo: true);
    final info = await api.signForum('图拉丁');
    expect(info['is_sign_in'], 1);
    expect(writes.map((r) => r.url.path), [
      '/c/c/forum/like',
      '/c/c/forum/unfavolike',
      '/c/c/forum/sign',
    ]);
    for (final request in writes) {
      expect(request.url.host, 'tiebac.baidu.com');
      final body = {...request.bodyFields};
      expect(body['_client_version'], '22.12.1.0');
      expect(body['kw'], '图拉丁');
      expect(body['tbs'], 'test-token');
      final signature = body.remove('sign');
      final keys = body.keys.toList()..sort();
      expect(
        signature,
        md5
            .convert(
              utf8.encode(
                '${keys.map((key) => '$key=${body[key]}').join()}tiebaclient!!!',
              ),
            )
            .toString(),
      );
    }
  });

  test('nested follow rejection throws and is never retried', () async {
    final writes = <http.Request>[];
    final api = apiFor({
      'error': {'errno': 34, 'errmsg': '操作频繁，请稍后再试'},
    }, writes);
    addTearDown(api.close);
    await expectLater(
      api.followForum('图拉丁', '74075'),
      throwsA(
        isA<TiebaException>()
            .having((e) => e.message, 'message', '操作频繁，请稍后再试')
            .having((e) => e.uncertain, 'uncertain', false),
      ),
    );
    expect(writes, hasLength(1));
  });

  test('top-level sign rejection is preserved without retry', () async {
    final writes = <http.Request>[];
    final api = apiFor({'error_code': 34, 'error_msg': '操作频繁，请稍后再试'}, writes);
    addTearDown(api.close);
    await expectLater(
      api.signForum('图拉丁'),
      throwsA(
        isA<TiebaException>().having((e) => e.message, 'message', '操作频繁，请稍后再试'),
      ),
    );
    expect(writes, hasLength(1));
  });

  test('sign response without confirmation remains uncertain', () async {
    final writes = <http.Request>[];
    final api = apiFor({}, writes);
    addTearDown(api.close);
    await expectLater(
      api.signForum('图拉丁'),
      throwsA(
        isA<TiebaException>().having((e) => e.uncertain, 'uncertain', true),
      ),
    );
    expect(writes, hasLength(1));
  });
}
