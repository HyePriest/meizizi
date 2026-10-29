import 'dart:convert';
import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'auth_store.dart';
import 'models.dart';

class AppUpdate extends ChangeNotifier {
  AppUpdate._();
  static final instance = AppUpdate._();
  static String version = '';
  static const projectUrl = 'https://github.com/HyePriest/meizizi';
  static const releasesUrl = '$projectUrl/releases/latest';
  static final _versionPattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );
  static const _releasePath = '/HyePriest/meizizi/releases/';
  String _tag = '';
  String latest = '', notes = '', _download = '';
  String? error, checkError;
  bool checking = false, downloading = false, readyToInstall = false;
  DateTime? _checkedAt;
  bool get available =>
      version.isNotEmpty && newer(latest, version) && _download.isNotEmpty;
  String get downloadUrl => _download.isEmpty ? releasesUrl : _download;
  String get releaseUrl =>
      _tag.isEmpty ? releasesUrl : '$projectUrl/releases/tag/$_tag';

  bool _validDownload(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.path.startsWith('${_releasePath}download/') &&
        uri.path.endsWith('.apk');
  }

  // Prefer the ARM64 build, then a universal APK such as app-release.apk.
  // Do not select an APK explicitly built for another architecture.
  String? _selectDownload(Iterable<String> urls) {
    String? universal;
    for (final url in urls.where(_validDownload)) {
      final name = Uri.parse(url).pathSegments.last.toLowerCase();
      if (name.contains('arm64') || name.contains('aarch64')) return url;
      if (name.contains('armeabi') ||
          name.contains('armv7') ||
          name.contains('x86'))
        continue;
      universal ??= url;
    }
    return universal;
  }

  void _acceptRelease(String tag, String url, String body) {
    if (!_versionPattern.hasMatch(tag) || !_validDownload(url)) {
      throw const FormatException();
    }
    if (_download != url) readyToInstall = false;
    _tag = tag;
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
          !uri.path.startsWith(_releasePath)) {
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
          !uri.path.startsWith('${_releasePath}tag/')) {
        throw const FormatException();
      }
      final tag = uri.pathSegments.last;
      if (!_versionPattern.hasMatch(tag)) throw const FormatException();
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
      final url = _selectDownload(
        links.map((link) => uri.resolve(link.attributes['href']!).toString()),
      );
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
    final a = _versionPattern.firstMatch(candidate),
        b = _versionPattern.firstMatch(installed);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      final x = int.parse(a.group(i + 1)!);
      final y = int.parse(b.group(i + 1)!);
      if (x != y) return x > y;
    }
    final preA = a.group(4), preB = b.group(4);
    if (preA == null) return preB != null;
    if (preB == null) return false;
    final aa = preA.split('.'), bb = preB.split('.');
    for (var i = 0; i < aa.length && i < bb.length; i++) {
      if (aa[i] == bb[i]) continue;
      final x = int.tryParse(aa[i]), y = int.tryParse(bb[i]);
      if (x != null && y != null) return x > y;
      if (x != null) return false;
      if (y != null) return true;
      return aa[i].compareTo(bb[i]) > 0;
    }
    return aa.length > bb.length;
  }

  Future<void> check({bool force = false}) async {
    // Android release assets cannot update a Windows installation.
    if (Platform.isWindows) {
      version = await AuthStore.native.invokeMethod<String>('appVersion') ?? '';
      checkError = null;
      notifyListeners();
      return;
    }
    if (checking ||
        downloading ||
        (!force &&
            _checkedAt != null &&
            DateTime.now().difference(_checkedAt!) < const Duration(hours: 6)))
      return;
    checking = true;
    checkError = null;
    notifyListeners();
    final client = http.Client();
    try {
      version = await AuthStore.native.invokeMethod<String>('appVersion') ?? '';
      if (!_versionPattern.hasMatch(version)) {
        throw const FormatException('无法读取当前版本');
      }
      notifyListeners();
      try {
        // Release metadata is public; never attach Tieba credentials here.
        final response = await client
            .get(
              Uri.https(
                'api.github.com',
                '/repos/HyePriest/meizizi/releases/latest',
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
            !_versionPattern.hasMatch(tag))
          throw const FormatException();
        final assets = objects(data['assets']);
        final url = _selectDownload(
          assets.map((asset) => firstText([asset['browser_download_url']])),
        );
        if (url == null) throw const FormatException();
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
    } on PlatformException catch (e) {
      if (e.code == 'MISSING_UPDATE') readyToInstall = false;
      error = e.message ?? '更新下载或安装未完成，请重试';
    } catch (_) {
      error = '更新下载或安装未完成，可重试或使用浏览器下载';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }
}
