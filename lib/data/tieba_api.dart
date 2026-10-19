import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';
import 'post_protocol.dart';
export 'models.dart';

class SignSession {
  SignSession._(this.account, this._token);
  final String account, _token;
}

class TiebaApi {
  TiebaApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final AuthStore _auth = AuthStore.instance;
  final Map<String, int> _floors = {};
  final Map<String, TiebaPage> _firstPages = {};
  static String _tokenIdentity = '', _cachedToken = '';
  static DateTime? _tokenTime;
  static Future<String>? _tokenPending;
  static final Map<String, Json> _levelCache = {};
  static final Map<String, ({DateTime time, List<Json> users})> _bawuCache = {};
  bool _closed = false;
  void close() {
    _closed = true;
    _client.close();
  }

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
        !data.containsKey('no') &&
        !data.containsKey('errno')) {
      throw TiebaException(
        writing ? '发送结果未确认，请先刷新帖子核对。草稿已保留。' : '接口数据格式发生变化',
        uncertain: writing,
      );
    }
    if (number(data['error_code'] ?? data['no'] ?? data['errno']) != 0) {
      if (writing) {
        _cachedToken = '';
        _tokenTime = null;
      }
      throw TiebaException(
        firstText([
          data['error_msg'],
          data['errmsg'],
          object(data['error'])['usermsg'],
          object(data['error'])['errmsg'],
          if (data['error'] is String) data['error'],
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
        '_client_version': '22.12.1.0',
        'kw': name,
        'pn': '$page',
        'rn': '20',
        'sort_type': category == '最新发布'
            ? '1'
            : category == '热门'
            ? '3'
            : '0',
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
    final identity = _auth.bduss;
    if (_tokenIdentity != identity) {
      _tokenIdentity = identity;
      _cachedToken = '';
      _tokenTime = null;
      _tokenPending = null;
    }
    if (_cachedToken.isNotEmpty &&
        _tokenTime != null &&
        DateTime.now().difference(_tokenTime!) < const Duration(minutes: 3))
      return _cachedToken;
    if (_tokenPending != null) return _tokenPending!;
    final pending = _fetchToken(identity);
    _tokenPending = pending;
    try {
      return await pending;
    } finally {
      if (identical(_tokenPending, pending)) _tokenPending = null;
    }
  }

  Future<String> _fetchToken(String identity) async {
    final account = _auth.activeId;
    final session = await _session();
    if (_auth.activeId != account || _auth.bduss != identity)
      throw const TiebaException('账号已切换，请重新操作');
    final token = firstText([object(session['anti'])['tbs']]);
    if (token.isEmpty) throw const TiebaException('未能获取操作凭据，请重新登录');
    _cachedToken = token;
    _tokenTime = DateTime.now();
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

  Future<SignSession> prepareSignSession() async {
    final account = _auth.activeId;
    final token = await _token();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，签到已停止');
    return SignSession._(account, token);
  }

  Future<Json> signForum(String name, {SignSession? session}) async {
    final credentials = session ?? await prepareSignSession();
    if (!_auth.isLoggedIn || _auth.activeId != credentials.account) {
      throw const TiebaException('账号已切换或退出，签到已停止');
    }
    final result = await _request('/c/c/forum/sign', {
      'kw': name,
      'tbs': credentials._token,
      'net_type': '1',
    }, writing: true);
    final info = object(result.data['user_info']);
    if (result.data['error'] is Map || !flag(info['is_sign_in'])) {
      final message = firstText([
        object(result.data['error'])['usermsg'],
      ], '签到未确认，请刷新吧页面查看签到状态');
      throw TiebaException(
        message,
        uncertain:
            !message.contains('已签到') &&
            !message.contains('已经签到') &&
            !unavailableForumMessage(message),
      );
    }
    return info;
  }

  Future<void> followForum(String name, String id, {bool undo = false}) async {
    final account = _auth.activeId;
    final token = await _token();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    await _request(undo ? '/c/c/forum/unfavolike' : '/c/c/forum/like', {
      'kw': name,
      'forum_name': name,
      'fid': id,
      'tbs': token,
    }, writing: true);
  }

  Future<Json> forumLevels(String id) async {
    final key = '${_auth.activeId}:$id';
    if (_levelCache.containsKey(key)) return _levelCache[key]!;
    final data = (await _request('/c/f/forum/getLevelInfo', {
      'forum_id': id,
    })).data;
    if (_levelCache.length >= 40) _levelCache.remove(_levelCache.keys.first);
    _levelCache[key] = data;
    return data;
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

  Future<Uri> reportUrl(String postId) async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录');
    if (!RegExp(r'^[1-9]\d*$').hasMatch(postId)) {
      throw const TiebaException('举报对象无效，请重新打开帖子');
    }
    final account = _auth.activeId;
    // This only prepares the official form; it does not submit a report.
    final result = await _request('/c/f/ueg/checkjubao', {
      '_client_version': '12.25.1.0',
      'category': '1',
      'pid': postId,
      'cuid': _auth.deviceId,
    });
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    final uri = Uri.tryParse(firstText([object(result.data['data'])['url']]));
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        !(uri.host == 'baidu.com' || uri.host.endsWith('.baidu.com')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw const TiebaException('未能获取官方举报页面，请稍后重试');
    }
    return uri.replace(scheme: 'https');
  }

  Future<Json> agreeState(
    String threadId, {
    required String postId,
    bool comment = false,
    String? parentPostId,
  }) async {
    final account = _auth.activeId;
    Json? target;
    if (comment) {
      if (parentPostId == null) throw const TiebaException('请重新打开楼中楼');
      final result = await floor(
        threadId,
        parentPostId,
        1,
        targetReply: postId,
      );
      for (final reply in result.replies) {
        if ('${reply['id']}' == postId) target = reply;
      }
    } else {
      final result = await thread(
        threadId,
        1,
        targetPost: postId == '0' ? null : postId,
      );
      if (postId == '0') {
        target = object(result.data['thread']);
      } else {
        for (final post in result.posts) {
          if ('${post['id']}' == postId) target = post;
        }
      }
    }
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    final agree = object(target?['agree']);
    if (!agree.containsKey('has_agree') && !agree.containsKey('agree_type')) {
      throw const TiebaException('暂时无法确认点赞状态，请稍后重试');
    }
    return agree;
  }

  Future<TiebaPage> thread(
    String id,
    int page, {
    bool onlyAuthor = false,
    bool hot = false,
    bool descending = false,
    String? targetPost,
    void Function(Map<String, int>)? onFloorNumbers,
  }) async {
    if (hot) {
      return _hotPosts(
        id,
        page,
        onlyAuthor: onlyAuthor,
        onFloorNumbers: onFloorNumbers,
      );
    }
    final result = await _request('/c/f/pb/page', {
      '_client_version': '22.12.1.0',
      'kz': id,
      if (targetPost == null) 'pn': '$page',
      'rn': '20',
      'with_floor': '1',
      'floor_rn': '4',
      'floor_sort_type': '1',
      'lz': onlyAuthor ? '1' : '0',
      if (targetPost != null) 'pid': targetPost,
      'r': descending ? '1' : '0',
    });
    _rememberFloors(id, result.posts);
    if (page == 1 && targetPost == null && !descending)
      _firstPages['${_auth.activeId}:$id:$onlyAuthor'] = result;
    if (descending && page == 1 && targetPost == null) {
      final first =
          _firstPages['${_auth.activeId}:$id:$onlyAuthor'] ??
          await thread(id, 1, onlyAuthor: onlyAuthor);
      final firstPosts = first.posts.where((p) => number(p['floor']) == 1);
      final posts = result.posts.where((p) => number(p['floor']) != 1);
      return TiebaPage({
        ...result.data,
        'post_list': [...firstPosts, ...posts],
        'user_list': [
          ...objects(first.data['user_list']),
          ...objects(result.data['user_list']),
        ],
      });
    }
    return result;
  }

  void _rememberFloors(String tid, List<Json> posts) {
    for (final post in posts) {
      if (number(post['floor']) > 0) {
        _floors['$tid:${post['id']}'] = number(post['floor']);
      }
    }
  }

  Future<void> vote(String threadId, String forumId, List<int> options) async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录再投票');
    if (number(threadId) <= 0 ||
        number(forumId) <= 0 ||
        options.isEmpty ||
        options.any((id) => id <= 0) ||
        options.toSet().length != options.length) {
      throw const TiebaException('投票信息不完整，请刷新帖子后重试');
    }
    try {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.https('tiebac.baidu.com', '/c/c/post/addPollPost', {
                'cmd': '309006',
              }),
            )
            ..followRedirects = false
            ..headers['User-Agent'] = 'bdtb for Android 22.12.1.0'
            ..headers['x_bd_data_type'] = 'protobuf'
            ..files.add(
              http.MultipartFile.fromBytes(
                'data',
                encodePoll(
                  threadId,
                  forumId,
                  options,
                  bduss: _auth.bduss,
                  stoken: _auth.stoken,
                  cuid: _auth.deviceId,
                ),
                filename: 'file',
              ),
            );
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 25)),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw const TiebaException('投票结果未确认，请刷新帖子核对后再操作', uncertain: true);
      }
      final result = decodePollResponse(response.bodyBytes);
      // Require a structured error envelope; HTML/empty replies aren't success.
      if (result['error'] is! Map) {
        throw const FormatException('Missing vote acknowledgement');
      }
      final error = object(result['error']);
      if (number(error['errorno']) != 0) {
        throw TiebaException(firstText([error['errmsg']], '投票失败，请稍后重试'));
      }
    } on TimeoutException {
      throw const TiebaException('投票结果未确认，请刷新帖子核对后再操作', uncertain: true);
    } on http.ClientException {
      throw const TiebaException('连接中断，投票结果未确认，请刷新帖子核对', uncertain: true);
    } on FormatException {
      throw const TiebaException('投票结果未确认，请刷新帖子核对后再操作', uncertain: true);
    }
  }

  Future<TiebaPage> _hotPosts(
    String id,
    int page, {
    required bool onlyAuthor,
    void Function(Map<String, int>)? onFloorNumbers,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('c.tieba.baidu.com', '/c/f/pb/page', {'cmd': '302001'}),
          )
          ..followRedirects = false
          ..headers['User-Agent'] = 'bdtb for Android 22.12.1.0'
          ..headers['x_bd_data_type'] = 'protobuf'
          ..files.add(
            http.MultipartFile.fromBytes(
              'data',
              encodeHotPosts(
                id,
                page,
                bduss: _auth.bduss,
                stoken: _auth.stoken,
                cuid: _auth.deviceId,
                onlyAuthor: onlyAuthor,
              ),
              filename: 'file',
            ),
          );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 25)),
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw TiebaException('服务器返回 ${response.statusCode}，请重试');
    }
    Json result;
    try {
      result = decodePostResponse(response.bodyBytes);
    } on FormatException {
      throw const TiebaException('热度排序返回数据无法识别，请重试');
    }
    final error = object(result['error']);
    if (number(error['errorno']) != 0) {
      throw TiebaException(firstText([error['errmsg']], '热度排序加载失败'));
    }
    if (result['data'] is! Map) throw const TiebaException('热度排序未返回帖子内容');
    final data = object(result['data']);
    // JSON retains forum avatar and account-specific metadata; native posts supply the actual hot order.
    if (page == 1) {
      final metadata =
          _firstPages['${_auth.activeId}:$id:$onlyAuthor'] ??
          await thread(id, 1, onlyAuthor: onlyAuthor);
      data['forum'] = {
        ...object(metadata.data['forum']),
        ...object(data['forum']),
      };
      data['thread'] = {
        ...object(data['thread']),
        ...object(metadata.data['thread']),
      };
      final first = object(data['first_floor_post']);
      final firstPosts = first.isNotEmpty
          ? [first]
          : metadata.posts.where((p) => number(p['floor']) == 1).toList();
      final posts = objects(data['post_list']);
      final ids = posts.map((p) => '${p['id']}').toSet();
      data['post_list'] = [
        ...firstPosts.where((p) => !ids.contains('${p['id']}')),
        ...posts,
      ];
      data['user_list'] = [
        ...objects(metadata.data['user_list']),
        ...objects(data['user_list']),
      ];
    }
    final posts = objects(data['post_list']);
    _rememberFloors(id, posts);
    for (final post in posts) {
      final key = '$id:${post['id']}';
      post['floor'] = _floors[key];
      post['floor_pending'] = !_floors.containsKey(key);
    }
    data['post_list'] = posts;
    if (onFloorNumbers == null) {
      await _resolveFloorNumbers(id, posts);
      for (final post in posts) {
        post['floor'] = _floors['$id:${post['id']}'];
        post['floor_pending'] = false;
      }
    } else {
      // Let the hot list render immediately; only its floor labels update later.
      unawaited(
        Future<void>(() async {
          await _resolveFloorNumbers(id, posts, onFloorNumbers: onFloorNumbers);
        }),
      );
    }
    return TiebaPage(data);
  }

  Future<void> _resolveFloorNumbers(
    String id,
    List<Json> posts, {
    void Function(Map<String, int>)? onFloorNumbers,
  }) async {
    final pending = posts.map((p) => '${p['id']}').toSet().toList();
    while (pending.isNotEmpty && !_closed) {
      pending.removeWhere((pid) => _floors.containsKey('$id:$pid'));
      final batch = pending.take(4).toList();
      pending.removeWhere(batch.contains);
      await Future.wait(
        batch.map((pid) async {
          try {
            final around = await _request('/c/f/pb/page', {
              '_client_version': '12.24.1.0',
              'kz': id,
              'pid': pid,
              'rn': '30',
              'r': '0',
              'with_floor': '1',
            });
            _rememberFloors(id, around.posts);
          } catch (_) {
            // Missing labels must not hide an otherwise readable hot list.
          }
        }),
      );
      if (!_closed && onFloorNumbers != null) {
        onFloorNumbers({
          for (final post in posts)
            if (_floors.containsKey('$id:${post['id']}') || pending.isEmpty)
              '${post['id']}': _floors['$id:${post['id']}'] ?? 0,
        });
      }
    }
  }

  Future<TiebaPage> floor(
    String threadId,
    String postId,
    int page, {
    String? targetReply,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('c.tieba.baidu.com', '/c/f/pb/floor', {'cmd': '302002'}),
          )
          ..followRedirects = false
          ..headers['User-Agent'] = 'bdtb for Android 22.12.1.0'
          ..headers['x_bd_data_type'] = 'protobuf'
          ..files.add(
            http.MultipartFile.fromBytes(
              'data',
              encodeFloor(
                threadId,
                postId,
                page,
                bduss: _auth.bduss,
                stoken: _auth.stoken,
                cuid: _auth.deviceId,
                targetReply: targetReply,
              ),
              filename: 'file',
            ),
          );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 25)),
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw TiebaException('服务器返回 ${response.statusCode}');
    }
    final result = decodeFloorResponse(response.bodyBytes);
    final error = object(result['error']);
    if (number(error['errorno']) != 0) {
      throw TiebaException(firstText([error['errmsg']], '楼中楼加载失败'));
    }
    if (result['data'] is! Map) throw const TiebaException('楼中楼数据无法识别');
    return TiebaPage(object(result['data']));
  }

  Future<List<Json>> forumModerators(String fid) async {
    final cached = _bawuCache[fid];
    if (cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 15))
      return cached.users;
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('c.tieba.baidu.com', '/c/f/forum/getBawuInfo', {
              'cmd': '301007',
            }),
          )
          ..followRedirects = false
          ..headers['User-Agent'] = 'bdtb for Android 22.12.1.0'
          ..headers['x_bd_data_type'] = 'protobuf'
          ..files.add(
            http.MultipartFile.fromBytes(
              'data',
              encodeBawu(fid),
              filename: 'file',
            ),
          );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 15)),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw const TiebaException('吧务信息加载失败');
    final result = decodeBawuResponse(response.bodyBytes);
    if (number(object(result['error'])['errorno']) != 0)
      throw const TiebaException('吧务信息暂不可用');
    final users = <Json>[];
    for (final group in objects(
      object(object(result['data'])['team'])['groups'],
    )) {
      for (final user in objects(group['users'])) {
        users.add({
          ...user,
          'forum_role': firstText([user['forum_role'], group['role']]),
          'is_bawu': 1,
        });
      }
    }
    if (_bawuCache.length >= 40) _bawuCache.remove(_bawuCache.keys.first);
    _bawuCache[fid] = (time: DateTime.now(), users: users);
    return users;
  }

  Future<TiebaPage> floorDetails(String tid, String pid, int page) => _request(
    '/c/f/pb/floor',
    {'_client_version': '22.12.1.0', 'kz': tid, 'pid': pid, 'pn': '$page'},
  );

  Future<TiebaPage> threadAtFloor(String tid, int floor) async {
    final first = await thread(tid, 1);
    var result = first;
    var low = 1, high = number(object(result.data['page'])['total_page']);
    if (high < 1) high = 1;
    var best = result;
    while (low <= high) {
      final page = (low + high) ~/ 2;
      result = page == 1 ? first : await thread(tid, page);
      final floors =
          result.posts
              .map((p) => number(p['floor']))
              .where((n) => n > 0)
              .toList()
            ..sort();
      if (floors.isEmpty) {
        high = page - 1;
        continue;
      }
      best = result;
      if (floor < floors.first) {
        high = page - 1;
      } else if (floor > floors.last) {
        low = page + 1;
      } else {
        return result;
      }
    }
    return best;
  }

  Future<TiebaPage> savedThreads(int page) =>
      _request('/c/f/post/threadstore', {
        '_client_version': '11.10.8.6',
        'rn': '20',
        'offset': '${(page - 1) * 20}',
        'user_id': firstText([_auth.user['id'], _auth.user['user_id']]),
      });

  Future<void> saveThread(
    String tid,
    String pid, {
    required bool remove,
  }) async {
    final account = _auth.activeId;
    final token = await _token();
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新操作');
    await _request(remove ? '/c/c/post/rmstore' : '/c/c/post/addstore', {
      '_client_version': '12.24.1.0',
      'tbs': token,
      if (remove) 'tid': tid,
      if (!remove)
        'data': jsonEncode([
          {'tid': tid, 'pid': pid, 'status': 1},
        ]),
    }, writing: true);
  }

  Future<Json> messageCounts() async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录');
    final account = _auth.activeId;
    final result = await _request('/c/s/msg', {
      '_client_version': '12.64.1.1',
      'bookmark': '1',
    });
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新加载');
    return object(result.data['message']);
  }

  Future<MessageBatch> messages(
    MessageKind kind,
    int page, {
    String cursor = '',
  }) async {
    if (!_auth.isLoggedIn) throw const TiebaException('请先登录');
    final account = _auth.activeId;
    Json data;
    if (kind == MessageKind.likes) {
      final response = await _webGet('/mo/q/smallapp/agreeme', {
        'rn': '20',
        'id': cursor,
      });
      data = object(response['data']);
    } else {
      data = (await _request(
        '/c/u/feed/${kind == MessageKind.replies ? 'replyme' : 'atme'}',
        {'_client_version': '12.64.1.1', 'pn': '$page', 'rn': '20'},
      )).data;
    }
    if (_auth.activeId != account) throw const TiebaException('账号已切换，请重新打开消息');
    final key = switch (kind) {
      MessageKind.replies => 'reply_list',
      MessageKind.likes => 'agree_list',
      MessageKind.mentions => 'at_list',
    };
    if (!data.containsKey(key) &&
        !data.containsKey('page') &&
        !data.containsKey('has_more')) {
      throw const TiebaException('消息数据暂不可用，请稍后重试');
    }
    final items = objects(data[key]);
    final next = items.isEmpty ? '' : firstText([items.last['id']]);
    final more = flag(data['has_more'] ?? object(data['page'])['has_more']);
    return MessageBatch(
      items,
      more &&
          items.isNotEmpty &&
          (kind != MessageKind.likes || (next.isNotEmpty && next != cursor)),
      cursor: next,
    );
  }

  Future<String> currentUserIp(Json user) async {
    final result = await _request('/c/u/user/profile', {
      '_client_version': '12.64.1.1',
      'uid': firstText([_auth.user['id'], _auth.user['user_id']], '0'),
      'friend_uid': firstText([user['id'], user['user_id']]),
      'friend_uid_portrait': firstText([user['portrait']]),
      'is_guest': '1',
      'has_plist': '0',
      'need_post_count': '0',
      'pn': '1',
      'page': '1',
    });
    return postIp({}, object(result.data['user']));
  }

  Future<TiebaPage> userProfile(Json user) => _request('/c/u/user/profile', {
    '_client_version': '12.64.1.1',
    'uid': firstText([_auth.user['id'], _auth.user['user_id']], '0'),
    'friend_uid': firstText([user['id'], user['user_id']]),
    'friend_uid_portrait': firstText([user['portrait']]),
    'is_guest': userKey(user) == userKey(_auth.user) && _auth.isLoggedIn
        ? '0'
        : '1',
    'has_plist': '1',
    'need_post_count': '1',
    'pn': '1',
    'page': '1',
  });
  Future<TiebaPage> userPosts(
    String uid,
    int page, {
    bool replies = false,
  }) async {
    final result = await _request('/c/u/feed/userpost', {
      'uid': uid,
      'pn': '$page',
      'rn': '20',
      '_client_version': replies ? '7.2.0' : '8.2.2',
      'is_thread': replies ? '0' : '1',
      'need_content': '1',
      'is_view_card': '1',
      'q_type': '80',
    });
    if (!replies) return result;
    // Reply history groups a user's own replies by thread. Each group carries
    // post_content; treating the group itself as a content part loses the text.
    final posts = <Json>[];
    for (final item in objects(result.data['post_list'])) {
      final groups = objects(item['content']);
      if (groups.any((group) => group.containsKey('post_content'))) {
        for (final group in groups) {
          posts.add({
            ...item,
            'content': group['post_content'],
            'post_id': group['post_id'] ?? item['post_id'],
            'create_time': group['create_time'] ?? item['create_time'],
          });
        }
      } else {
        posts.add(item);
      }
    }
    return TiebaPage({...result.data, 'post_list': posts});
  }

  Future<SearchResult> userFollows(
    String uid,
    int page, {
    bool fans = false,
  }) async {
    final result = await _request(
      fans ? '/c/u/fans/page' : '/c/u/follow/followList',
      {'_client_version': '12.24.1.0', 'uid': uid, 'pn': '$page'},
    );
    return SearchResult(
      objects(result.data[fans ? 'user_list' : 'follow_list']),
      flag(
        fans
            ? object(result.data['page'])['has_more']
            : result.data['has_more'],
      ),
    );
  }

  Future<SearchResult> userForums(String uid, int page) async {
    final result = await _request('/c/f/forum/like', {
      '_client_version': '12.24.1.0',
      'uid': firstText([_auth.user['id']], '0'),
      'friend_uid': uid,
      'page_no': '$page',
      'page_size': '50',
      'allow_guest': '1',
      'is_guest': _auth.isLoggedIn ? '0' : '1',
      'need_member': '1',
    });
    final raw = result.data['forum_list'];
    final nested = object(raw);
    return SearchResult(
      raw is List
          ? objects(raw)
          : [
              ...objects(nested['gconforum']),
              ...objects(nested['non-gconforum']),
            ],
      flag(result.data['has_more']),
    );
  }

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
