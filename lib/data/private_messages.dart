import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';

/// The official PC inbox's read APIs, rendered with the app's native interface.
class PrivateMessagesApi {
  final _client = http.Client();
  final String account = AuthStore.instance.activeId;
  void close() => _client.close();

  Future<Json> _request(
    String action,
    Map<String, String> query, {
    bool post = false,
  }) async {
    final auth = AuthStore.instance;
    if (!auth.isLoggedIn || account != auth.activeId)
      throw const TiebaException('账号已切换，请重新打开私信');
    final request =
        http.Request(
            post ? 'POST' : 'GET',
            Uri.https('c.tieba.baidu.com', '/im/pcmsg/query/$action', {
              ...query,
              'noCache': '${DateTime.now().millisecondsSinceEpoch}',
            }),
          )
          ..followRedirects = false
          ..headers.addAll({
            'Cookie': auth.cookieHeader,
            'Referer': 'https://c.tieba.baidu.com/im/pcmsg',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
            'X-Requested-With': 'XMLHttpRequest',
          });
    if (post) request.bodyFields = {'cuid': auth.baiduid};
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 18)),
    ).timeout(const Duration(seconds: 18));
    if (account != auth.activeId) throw const TiebaException('账号已切换，请重新打开私信');
    if (response.statusCode != 200)
      throw const TiebaException('私信暂时无法加载，请重新登录后重试');
    Json data;
    try {
      data = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      throw const TiebaException('私信需要重新验证登录，请点击右上角登录');
    }
    if (!data.containsKey('errno'))
      throw const TiebaException('私信接口暂不可用，请稍后重试');
    if (number(data['errno']) != 0)
      throw TiebaException(
        firstText([data['errmsg'], data['error']], '私信读取失败，请重新登录后重试'),
      );
    return data;
  }

  Future<({List<Json> items, bool more, int pageSize})> contacts(
    int offset,
  ) async {
    final result = object(
      (await _request('getContacts', {'offset': '$offset'}))['data'],
    );
    if (result['contacts'] is! List) throw const TiebaException('私信联系人暂不可用');
    final items = objects(result['contacts']);
    final pageSize = number(result['pageSize']);
    final size = pageSize > 0 ? pageSize : 30;
    return (items: items, more: items.length >= size, pageSize: size);
  }

  Future<List<Json>> messages(String uid, {String before = '0'}) async {
    final result = await _request('getMsg', {
      'chatUid': uid,
      'lastMsgId': before,
      'cuid': AuthStore.instance.baiduid,
    }, post: true);
    if (result['data'] is! List) throw const TiebaException('聊天记录暂不可用');
    return objects(result['data']);
  }
}
