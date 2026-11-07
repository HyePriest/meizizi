import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_webview.dart';
import 'models.dart';
import 'platform_session.dart';
import 'serial_tasks.dart';

class AuthStore extends ChangeNotifier {
  AuthStore._();
  static final instance = AuthStore._();
  static const native = PlatformSession();
  static const _storage = FlutterSecureStorage();
  // Secure-storage keys. These names are the on-disk format: never rename.
  static const _deviceIdKey = 'anonymous_device_id';
  static const _accountsKey = 'baidu_accounts';
  static const _legacySessionKey = 'baidu_session';
  List<Json> _accounts = [];
  String _active = '';

  // Account changes run one at a time so a switch cannot interleave with a
  // login or removal.
  final _changes = SerialTasks();
  Future<void> _change(Future<void> Function() action) => _changes.run(action);

  List<Json> get accounts =>
      _accounts.map((a) => {'id': a['id'], 'user': object(a['user'])}).toList();
  String get activeId => _active;
  Json get _session =>
      _accounts.firstWhere((a) => a['id'] == _active, orElse: () => {});
  Json get user => object(_session['user']);
  Map<String, String> get _cookies =>
      object(_session['cookies']).map((k, v) => MapEntry(k, '$v'));
  String deviceId = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  bool get isLoggedIn => bduss.isNotEmpty;
  bool get isGuest => !isLoggedIn;
  String get bduss => firstText([_cookies['BDUSS'], _cookies['BDUSS_BFESS']]);
  String get stoken =>
      firstText([_cookies['STOKEN'], _cookies['STOKEN_BFESS']]);
  String get baiduid => _cookies['BAIDUID'] ?? '';
  String get cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> restore() async {
    try {
      final savedDevice = await _storage.read(key: _deviceIdKey);
      if (savedDevice != null && savedDevice.isNotEmpty) {
        deviceId = savedDevice;
      } else {
        await _storage.write(key: _deviceIdKey, value: deviceId);
      }
    } catch (_) {
      // Browsing can still use this launch's random ID if storage is unavailable.
    }
    try {
      final saved = await _storage.read(key: _accountsKey);
      if (saved != null) {
        final data = object(jsonDecode(saved));
        _accounts = objects(data['accounts']);
        _active = '${data['active'] ?? ''}';
      } else {
        final legacy = await _storage.read(key: _legacySessionKey);
        if (legacy != null) {
          final data = object(jsonDecode(legacy));
          final profile = object(data['user']);
          final id = firstText([profile['id'], profile['user_id']], 'legacy');
          _accounts = [
            {'id': id, 'user': profile, 'cookies': object(data['cookies'])},
          ];
          _active = id;
          await _persist(_accounts, _active);
          await _storage.delete(key: _legacySessionKey);
        }
      }
    } catch (_) {
      _accounts = [];
      _active = '';
    }
  }

  Future<void> _persist(List<Json> accounts, String active) => _storage.write(
    key: _accountsKey,
    value: jsonEncode({'accounts': accounts, 'active': active}),
  );
  static Future<void> _setBaiduCookie(
    WebViewCookieManager manager,
    String name,
    String value,
  ) => manager.setCookie(
    WebViewCookie(name: name, value: value, domain: '.baidu.com', path: '/'),
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
      await _setBaiduCookie(manager, entry.key, entry.value);
    }
  }

  Future<void> save(Map<String, String> cookies, Json profile) =>
      _change(() async {
        final id = firstText([profile['id'], profile['user_id']]);
        if (id.isEmpty) throw const TiebaException('无法取得账号标识，请重新登录');
        final updated = [
          ..._accounts.where((a) => a['id'] != id),
          {'id': id, 'user': profile, 'cookies': cookies},
        ];
        await _persist(updated, id);
        _accounts = updated;
        _active = id;
        await _storage.delete(key: _legacySessionKey);
        notifyListeners();
      });

  /// Merges public profile fields (such as the `name_show` nickname, which the
  /// login session leaves out for accounts without a username) into a saved
  /// account. Cookies are untouched.
  Future<void> updateProfile(String id, Json profile) => _change(() async {
    final index = _accounts.indexWhere((a) => a['id'] == id);
    if (index < 0) return;
    final account = _accounts[index];
    final merged = {...object(account['user']), ...profile};
    if (jsonEncode(merged) == jsonEncode(object(account['user']))) return;
    final updated = [..._accounts]..[index] = {...account, 'user': merged};
    await _persist(updated, _active);
    _accounts = updated;
    notifyListeners();
  });

  Future<void> switchAccount(String id) => _change(() async {
    if (id == _active) return;
    final account = _accounts.firstWhere(
      (a) => a['id'] == id,
      orElse: () => {},
    );
    if (account.isEmpty) throw const TiebaException('该账号已被移除');
    final manager = WebViewCookieManager();
    await manager.clearCookies();
    for (final entry in object(account['cookies']).entries) {
      await _setBaiduCookie(manager, entry.key, '${entry.value}');
    }
    await _persist(_accounts, id);
    _active = id;
    notifyListeners();
  });

  Future<void> removeAccount(String id) => _change(() async {
    if (id == _active) await native.invokeMethod<void>('clearBaiduCookies');
    final updated = _accounts.where((a) => a['id'] != id).toList();
    final next = id == _active ? '' : _active;
    await _persist(updated, next);
    _accounts = updated;
    _active = next;
    notifyListeners();
  });

  Future<void> enterGuestMode() => _change(() async {
    await native.invokeMethod<void>('clearBaiduCookies');
    await _persist(_accounts, '');
    _active = '';
    notifyListeners();
  });

  Future<void> logout() => removeAccount(_active);
}
