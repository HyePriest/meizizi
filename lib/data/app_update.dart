import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';

class AppUpdate extends ChangeNotifier {
  AppUpdate._();
  static final instance = AppUpdate._();
  static const version = '0.10.12';
  static const projectUrl = 'https://github.com/HyePriest/tieba';
  static const releasesUrl = '$projectUrl/releases/latest';
  String latest = '', notes = '', _download = '';
  String? error, checkError;
  bool checking = false, downloading = false, readyToInstall = false;
  DateTime? _checkedAt;
  bool get available => newer(latest, version) && _download.isNotEmpty;
  String get downloadUrl => _download.isEmpty ? releasesUrl : _download;
  String get releaseUrl =>
      latest.isEmpty ? releasesUrl : '$projectUrl/releases/tag/v$latest';

  bool _validDownload(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.path.startsWith('/HyePriest/tieba/releases/download/') &&
        uri.path.endsWith('.apk');
  }

  void _acceptRelease(String tag, String url, String body) {
    if (!RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag) || !_validDownload(url)) {
      throw const FormatException();
    }
    if (_download != url) readyToInstall = false;
    latest = tag.replaceFirst(RegExp(r'^v'), '');
    notes = body;
    _download = url;
    _checkedAt = DateTime.now();
  }

  Future<void> _checkWebRelease(http.Client client) async {
    var uri = Uri.parse(releasesUrl);
    for (var redirects = 0; redirects < 5; redirects++) {
      if (uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/HyePriest/tieba/releases/')) {
        throw const FormatException();
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['User-Agent'] = 'Tieba/$version';
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null) throw const FormatException();
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200 ||
          !uri.path.startsWith('/HyePriest/tieba/releases/tag/')) {
        throw const FormatException();
      }
      final tag = uri.pathSegments.last;
      if (!RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(tag))
        throw const FormatException();
      final assets = await client
          .get(
            Uri.parse('$projectUrl/releases/expanded_assets/$tag'),
            headers: {'User-Agent': 'Tieba/$version'},
          )
          .timeout(const Duration(seconds: 12));
      if (assets.statusCode != 200) throw const FormatException();
      final links = html
          .parse(utf8.decode(assets.bodyBytes))
          .querySelectorAll('a[href]');
      final url = links
          .map((link) => uri.resolve(link.attributes['href']!).toString())
          .where(
            (url) =>
                _validDownload(url) &&
                Uri.parse(url).pathSegments.last
                    .toLowerCase()
                    .contains('arm64'),
          )
          .firstOrNull;
      if (url == null) throw const FormatException();
      final document = html.parse(utf8.decode(response.bodyBytes));
      final body =
          document.querySelector('.release-entry .markdown-body') ??
          document.querySelector('.markdown-body');
      _acceptRelease(tag, url, body?.text.trim() ?? '');
      return;
    }
    throw const FormatException();
  }

  Future<void> openLink(String url) async {
    try {
      await AuthStore.native.invokeMethod<void>('openUpdateLink', {'url': url});
    } on PlatformException {
      error = '无法打开浏览器，请复制下方地址';
      notifyListeners();
    }
  }

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
    checkError = null;
    notifyListeners();
    final client = http.Client();
    try {
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
            .timeout(const Duration(seconds: 12));
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
                      RegExp(r'^tieba-.*arm64.*\.apk$')
                          .hasMatch('${a['name']}'),
                )
                .firstOrNull ??
            <String, dynamic>{};
        final url = firstText([asset['browser_download_url']]);
        _acceptRelease(tag, url, firstText([data['body']]));
      } catch (_) {
        // Public release pages remain usable when the unauthenticated API is rate limited.
        await _checkWebRelease(client);
      }
    } catch (_) {
      checkError = '暂时无法获取最新版本，可重试或打开下方最新发布页下载';
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
      error = '更新下载或安装未完成，可重试或使用浏览器下载';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }
}
