import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models.dart';

class AuthStore extends ChangeNotifier {
  AuthStore._();
  static final instance = AuthStore._();
  static const native = MethodChannel('com.jknl.tieba/session');
  static const _storage = FlutterSecureStorage();
  List<Json> _accounts = [];
  String _active = '';
  List<Json> get accounts =>
      _accounts.map((a) => {'id': a['id'], 'user': object(a['user'])}).toList();
  String get activeId => _active;
  Json get _session =>
      _accounts.firstWhere((a) => a['id'] == _active, orElse: () => {});
  Json get user => object(_session['user']);
  Map<String, String> get _cookies =>
      object(_session['cookies']).map((k, v) => MapEntry(k, '$v'));
  final String deviceId = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  bool get isLoggedIn => bduss.isNotEmpty;
  String get bduss => _cookies['BDUSS'] ?? _cookies['BDUSS_BFESS'] ?? '';
  String get stoken => _cookies['STOKEN'] ?? _cookies['STOKEN_BFESS'] ?? '';
  String get baiduid => _cookies['BAIDUID'] ?? '';
  String get cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> restore() async {
    try {
      final saved = await _storage.read(key: 'baidu_accounts');
      if (saved != null) {
        final data = object(jsonDecode(saved));
        _accounts = objects(data['accounts']);
        _active = '${data['active'] ?? ''}';
      } else {
        final legacy = await _storage.read(key: 'baidu_session');
        if (legacy != null) {
          final data = object(jsonDecode(legacy));
          final profile = object(data['user']);
          final id = firstText([profile['id'], profile['user_id']], 'legacy');
          _accounts = [
            {'id': id, 'user': profile, 'cookies': object(data['cookies'])},
          ];
          _active = id;
          await _persist(_accounts, _active);
          await _storage.delete(key: 'baidu_session');
        }
      }
    } catch (_) {
      _accounts = [];
      _active = '';
    }
  }

  Future<void> _persist(List<Json> accounts, String active) => _storage.write(
    key: 'baidu_accounts',
    value: jsonEncode({'accounts': accounts, 'active': active}),
  );
  Future<Map<String, String>> webCookies() async =>
      await native.invokeMapMethod<String, String>('getBaiduCookies') ?? {};
  Future<void> prepareNewLogin() =>
      native.invokeMethod<void>('clearBaiduCookies');
  Future<void> syncWebSession() async {
    final identity = _active;
    final cookies = Map<String, String>.from(_cookies);
    // Account switching already clears the WebView cookie jar. Keep the current
    // web session's auxiliary cookies so opening the inbox won't reset it.
    final manager = WebViewCookieManager();
    for (final entry in cookies.entries) {
      if (_active != identity) throw const TiebaException('账号已切换，请重新打开');
      await manager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: '.baidu.com',
          path: '/',
        ),
      );
    }
  }

  Future<void> save(Map<String, String> cookies, Json profile) async {
    final id = firstText([profile['id'], profile['user_id']]);
    if (id.isEmpty) throw const TiebaException('无法取得账号标识，请重新登录');
    final updated = [
      ..._accounts.where((a) => a['id'] != id),
      {'id': id, 'user': profile, 'cookies': cookies},
    ];
    await _persist(updated, id);
    _accounts = updated;
    _active = id;
    await _storage.delete(key: 'baidu_session');
    notifyListeners();
  }

  Future<void> switchAccount(String id) async {
    if (id == _active) return;
    final account = _accounts.firstWhere(
      (a) => a['id'] == id,
      orElse: () => {},
    );
    if (account.isEmpty) throw const TiebaException('该账号已被移除');
    final manager = WebViewCookieManager();
    await manager.clearCookies();
    for (final entry in object(account['cookies']).entries) {
      await manager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: '${entry.value}',
          domain: '.baidu.com',
          path: '/',
        ),
      );
    }
    await _persist(_accounts, id);
    _active = id;
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    if (id == _active) await native.invokeMethod<void>('clearBaiduCookies');
    final updated = _accounts.where((a) => a['id'] != id).toList();
    final next = id == _active ? '' : _active;
    await _persist(updated, next);
    _accounts = updated;
    _active = next;
    notifyListeners();
  }

  Future<void> logout() => removeAccount(_active);
}
