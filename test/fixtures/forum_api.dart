import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/tieba_api.dart';

class ForumApi extends TiebaApi {
  ForumApi() : super(client: MockClient((_) async => http.Response('{}', 200)));
  bool serverFollowed = true;
  final writes = <bool>[];
  Future<void> Function(bool followed)? write;
  Future<TiebaPage> Function()? read;
  Future<Json> Function()? sign;
  int signs = 0;
  Json get forumData => {
    'id': 74075,
    'name': '状态测试',
    'is_like': serverFollowed ? 1 : 0,
    'avatar': 'https://example.com/forum.png',
  };

  @override
  Future<TiebaPage> forum(
    String name,
    int page, {
    String category = '最新回复',
    ForumSection? section,
    String forumId = '',
    String lastThreadId = '0',
  }) async => read != null
      ? await read!()
      : TiebaPage({
          'forum': forumData,
          'thread_list': <Json>[],
          'page': {'has_more': 0},
        });

  @override
  Future<void> followForum(String name, String id, {bool undo = false}) async {
    writes.add(!undo);
    if (write != null) await write!(!undo);
  }

  @override
  Future<Json> signForum(String name, {SignSession? session}) async {
    signs++;
    return sign != null ? await sign!() : {'is_sign_in': 1};
  }

  @override
  Future<Json> forumLevels(String id) async => {};
  @override
  Future<Json> forumRules(String id) async => {};
  @override
  Future<List<Json>> forumModerators(String id) async => [];
}
