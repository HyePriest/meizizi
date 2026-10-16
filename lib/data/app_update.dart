import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';

class AppUpdate extends ChangeNotifier {
  AppUpdate._();
  static final instance = AppUpdate._();
  static const version = '0.9.1';
  String latest = '', notes = '', _download = '';
  String? error;
  bool checking = false, downloading = false, readyToInstall = false;
  DateTime? _checkedAt;
  bool get available => newer(latest, version) && _download.isNotEmpty;
  static bool newer(String candidate, String installed) {
    List<int> parts(String value) => value
        .replaceFirst(RegExp(r'^v'), '')
        .split('.')
        .map((n) => int.tryParse(n) ?? 0)
        .toList();
    final a = parts(candidate), b = parts(installed);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<void> check({bool force = false}) async {
    if (checking ||
        (!force &&
            _checkedAt != null &&
            DateTime.now().difference(_checkedAt!) < const Duration(hours: 6)))
      return;
    checking = true;
    error = null;
    notifyListeners();
    final client = http.Client();
    try {
      // Release metadata is public; never attach Tieba credentials here.
      final response = await client
          .get(
            Uri.https(
              'api.github.com',
              '/repos/HyePriest/tieba/releases/latest',
            ),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Tieba/$version',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw const FormatException();
      final data = object(jsonDecode(utf8.decode(response.bodyBytes)));
      final tag = firstText([data['tag_name']]);
      if (flag(data['draft']) ||
          flag(data['prerelease']) ||
          !RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag))
        throw const FormatException();
      final assets = objects(data['assets']);
      final asset =
          assets
              .where(
                (a) =>
                    RegExp(r'^tieba-.*arm64.*\.apk$').hasMatch('${a['name']}'),
              )
              .firstOrNull ??
          <String, dynamic>{};
      final url = firstText([asset['browser_download_url']]);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/HyePriest/tieba/releases/download/')) {
        throw const FormatException();
      }
      if (_download != url) readyToInstall = false;
      latest = tag.replaceFirst('v', '');
      notes = firstText([data['body']]);
      _download = url;
      _checkedAt = DateTime.now();
    } catch (_) {
      error = '暂时无法检查更新，点击重试';
    } finally {
      client.close();
      checking = false;
      notifyListeners();
    }
  }

  Future<void> install() async {
    if (!available || downloading) return;
    downloading = true;
    error = null;
    notifyListeners();
    try {
      final installing = readyToInstall;
      final result = await AuthStore.native.invokeMethod<String>(
        installing ? 'installUpdate' : 'downloadUpdate',
        installing ? null : {'url': _download},
      );
      if (result == 'ready') readyToInstall = true;
      if (result == 'permission') error = '允许此应用安装更新后，点击继续更新';
    } catch (_) {
      error = '更新下载或安装未完成，点击重试';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }
}
