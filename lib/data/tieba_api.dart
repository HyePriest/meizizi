import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';
export 'models.dart';

class TiebaApi {
  final http.Client _client = http.Client();
  final AuthStore _auth = AuthStore.instance;
  void close() => _client.close();

  Json _decode(
    http.Response response, {
    bool requireCode = true,
    bool writing = false,
  }) {
    if (response.statusCode != 200) {
      throw TiebaException(
        writing
            ? '发送结果未确认，请刷新帖子核对。草稿已保留。'
            : '服务器返回 ${response.statusCode}，请稍后重试',
        uncertain: writing,
      );
    }
    Json data;
    try {
      data = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      throw TiebaException(
        writing ? '发送结果未确认，请先刷新帖子核对。草稿已保留。' : '返回数据无法识别，可能需要在官方页面完成验证',
        uncertain: writing,
      );
    }
    if (requireCode &&
        !data.containsKey('error_code') &&
        !data.containsKey('no')) {
      throw TiebaException(
        writing ? '发送结果未确认，请先刷新帖子核对。草稿已保留。' : '接口数据格式发生变化',
        uncertain: writing,
      );
    }
    if (number(data['error_code'] ?? data['no']) != 0) {
      throw TiebaException(
        firstText([
          data['error_msg'],
          data['errmsg'],
          data['error'],
        ], '请求失败，请稍后重试'),
      );
    }
    return data;
  }

  Future<TiebaPage> _request(
    String path,
    Map<String, String> parameters, {
    bool writing = false,
  }) async {
    final body = <String, String>{
      '_client_type': '2',
      '_client_version': '8.2.2',
      if (_auth.isLoggedIn) 'BDUSS': _auth.bduss,
      if (_auth.stoken.isNotEmpty) 'stoken': _auth.stoken,
      ...parameters,
    };
    final keys = body.keys.toList()..sort();
    body['sign'] = md5
        .convert(
          utf8.encode(
            '${keys.map((k) => '$k=${body[k]}').join()}tiebaclient!!!',
          ),
        )
        .toString();
    try {
      final request = http.Request('POST', Uri.https('c.tieba.baidu.com', path))
        ..followRedirects = false
        ..headers['User-Agent'] = 'bdtb for Android ${body['_client_version']}'
        ..bodyFields = body;
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 25)),
      ).timeout(const Duration(seconds: 25));
      final data = _decode(response, writing: writing);
      if (writing && flag(data['need_vcode'])) {
        throw const TiebaException('需要验证码，请在官方页面完成验证后再发送');
      }
      return TiebaPage(data);
    } on TimeoutException {
      throw TiebaException(
        writing ? '发送结果未确认，请先刷新帖子确认，避免重复回复。草稿已保留。' : '请求超时，请检查网络后重试',
        uncertain: writing,
      );
    } on http.ClientException {
      throw TiebaException(
        writing ? '连接中断，发送结果未确认。请先刷新帖子确认，草稿已保留。' : '无法连接贴吧，请检查网络',
        uncertain: writing,
      );
    }
  }

  Future<Json> _webGet(
    String path,
    Map<String, String> query, {
    String? cookies,
    bool requireCode = true,
  }) async {
    var uri = Uri.https('tieba.baidu.com', path, query);
    final cookie = cookies ?? _auth.cookieHeader;
    for (var redirects = 0; redirects < 4; redirects++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36'
        ..headers['Referer'] = 'https://tieba.baidu.com/';
      if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 20));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) break;
        final next = uri.resolve(location);
        if (next.host != 'tieba.baidu.com' ||
            !['http', 'https'].contains(next.scheme)) {
          break;
        }
        final secure = next.replace(scheme: 'https');
        if (secure == uri) break;
        uri = secure;
        continue;
      }
      return _decode(response, requireCode: requireCode);
    }
    throw const TiebaException('百度网页接口跳转异常，请稍后再试');
  }

  Future<TiebaPage> forum(String name, int page, {String category = '最新回复'}) =>
      _request('/c/f/frs/page', {
        'kw': name,
        'pn': '$page',
        'rn': '20',
        'sort_type': category == '最新发布'
            ? '1'
            : category == '热门'
            ? '3'
            : '6',
        if (category == '精华') 'is_good': '1',
        if (category == '精华') 'cid': '0',
      });

  Future<TiebaPage> home(int page) => _request('/c/f/excellent/personalized', {
    '_client_version': '8.0.8.0',
    'page_thread_count': '20',
    'pn': '$page',
    'pre_ad_thread_count': '0',
    'load_type': '1',
    'invoke_source': '',
    'request_time': '${DateTime.now().millisecondsSinceEpoch}',
  });

  Future<Json> _session([String? bduss]) async {
    final session = await _request('/c/s/login', {
      '_client_version': '12.24.1.0',
      'BDUSS': bduss ?? _auth.bduss,
      'bdusstoken': bduss ?? _auth.bduss,
      // Confirm only this session, even when replacing a previously saved account.
      'stoken': '',
    });
    if (firstText([object(session.data['user'])['id']]).isEmpty ||
        number(object(session.data['user'])['id']) == 0) {
      throw const TiebaException('登录已失效，请重新完成官方网页登录');
    }
    return session.data;
  }

  Future<String> _token() async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录');
    final account = _auth.activeId;
    final session = await _session();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    final token = firstText([object(session['anti'])['tbs']]);
    if (token.isEmpty) throw const TiebaException('未能获取操作凭据，请重新登录');
    return token;
  }

  Future<SearchResult> followedForums(int page) async {
    final account = _auth.activeId;
    final session = await _session();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新加载');
    final result = await _request('/c/f/forum/like', {
      'uid': '${object(session['user'])['id']}',
      'friend_uid': '',
      'tbs': '${object(session['anti'])['tbs'] ?? ''}',
      'page_no': '$page',
      'page_size': '50',
      'need_member': '1',
      'allow_guest': '1',
      'is_guest': '',
      'q_type': '80',
    });
    final raw = result.data['forum_list'];
    final nested = object(raw);
    final forums = raw is List
        ? objects(raw)
        : [
            ...objects(nested['gconforum']),
            ...objects(nested['non-gconforum']),
          ];
    return SearchResult(forums, flag(result.data['has_more']));
  }

  Future<Json> signForum(String name) async {
    final token = await _token();
    final result = await _request('/c/c/forum/sign', {
      'kw': name,
      'tbs': token,
      'net_type': '1',
    }, writing: true);
    final info = object(result.data['user_info']);
    if (result.data['error'] is Map || !flag(info['is_sign_in'])) {
      throw TiebaException(
        firstText([
          object(result.data['error'])['usermsg'],
        ], '签到未确认，请刷新吧页面查看签到状态'),
      );
    }
    return info;
  }

  Future<void> agree(
    String threadId, {
    String postId = '0',
    bool comment = false,
    bool undo = false,
  }) async {
    final account = _auth.activeId;
    final token = await _token();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    final type = postId == '0'
        ? '3'
        : comment
        ? '2'
        : '1';
    await _request('/c/c/agree/opAgree', {
      '_client_version': '12.24.1.0',
      'agree_type': '2',
      'content_type': type,
      'obj_type': type,
      'op_type': undo ? '1' : '0',
      'post_id': postId,
      'thread_id': threadId,
      'tbs': token,
      'cuid': _auth.deviceId,
    }, writing: true);
  }

  Future<TiebaPage> thread(String id, int page, {bool onlyAuthor = false}) =>
      _request('/c/f/pb/page', {
        'kz': id,
        'pn': '$page',
        'rn': '20',
        'with_floor': '1',
        'floor_rn': '3',
        'lz': onlyAuthor ? '1' : '0',
      });
  Future<TiebaPage> floor(String threadId, String postId, int page) => _request(
    '/c/f/pb/floor',
    {'kz': threadId, 'pid': postId, 'pn': '$page', 'rn': '20'},
  );

  Future<SearchResult> search(
    String word,
    int page, {
    required bool forums,
  }) async {
    if (forums) {
      final response = await _webGet('/mo/q/seekforum', {
        'word': word,
        'pn': '$page',
        'rn': '20',
        'is_ajax': '1',
      });
      final nested = object(response['data']);
      if (number(nested['no']) != 0) {
        throw TiebaException('${nested['error'] ?? '搜索失败'}');
      }
      final data = object(nested['data']);
      final pagination = object(data['page']);
      return SearchResult(
        objects(data['forum']),
        number(pagination['cur_page']) < number(pagination['total_page']),
      );
    }
    final response = await _webGet('/mo/q/search/thread', {
      'word': word,
      'pn': '$page',
      'st': '2',
      'tt': '1',
    });
    final data = object(response['data']);
    return SearchResult(objects(data['post_list']), flag(data['has_more']));
  }

  Future<Json> acceptLogin(Map<String, String> cookies) async {
    final bduss = cookies['BDUSS'] ?? cookies['BDUSS_BFESS'] ?? '';
    if (bduss.isEmpty) throw const TiebaException('尚未取得登录状态，请在网页中完成登录');
    final session = await _session(bduss);
    final profile = object(session['user']);
    await _auth.save(cookies, profile);
    return profile;
  }

  Future<void> reply({
    required String threadId,
    required String forumName,
    required String forumId,
    required String content,
    String? postId,
    String? replyUid,
  }) async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录后再回复');
    final token = await _token();
    await _request('/c/c/post/add', {
      '_client_version': '12.24.1.0',
      'tbs': token,
      'tid': threadId,
      'fid': forumId,
      'kw': forumName,
      'content': content,
      'anonymous': '0',
      'authsid': 'null',
      'active_timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      'barrage_time': '0',
      'is_barrage': '0',
      'is_teenager': '0',
      'v_fid': '',
      'v_fname': '',
      'cmode': '1',
      'is_ad': '0',
      'is_feedback': '0',
      'entrance_type': '0',
      'takephoto_num': '0',
      'can_no_forum': '0',
      'baiduid': _auth.baiduid,
      'cuid': _auth.deviceId,
      'brand': 'Android',
      'net_type': '1',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      'quote_id': ?postId,
      'repostid': ?postId,
      if (postId != null) 'floor_num': '0',
      'reply_uid': replyUid?.isNotEmpty == true ? replyUid! : 'null',
    }, writing: true);
  }
}
