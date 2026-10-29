import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as desktop;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:url_launcher/url_launcher.dart';

export 'package:webview_flutter/webview_flutter.dart'
    show
        JavaScriptMode,
        NavigationDecision,
        NavigationRequest,
        WebResourceError,
        HttpResponseError,
        WebResourceRequest,
        WebViewCookie;

/// One persistent WebView2 profile shared by login and authenticated pages.
class DesktopWebSession {
  static desktop.WebViewEnvironment? environment;
  static Object? initializationError;
  static Future<void> initialize() async {
    if (!Platform.isWindows) return;
    final root = await getApplicationSupportDirectory();
    environment = await desktop.WebViewEnvironment.create(
      settings: desktop.WebViewEnvironmentSettings(
        userDataFolder: '${root.path}/WebView2',
      ),
    );
  }

  static desktop.CookieManager get cookies {
    if (initializationError != null) {
      throw StateError('内置浏览器未能启动，请安装 WebView2 后重启应用');
    }
    return desktop.CookieManager.instance(webViewEnvironment: environment);
  }

  static Future<Map<String, String>> baiduCookies() async {
    final result = <String, String>{};
    const allowed = {
      'BDUSS',
      'STOKEN',
      'BAIDUID',
      'BDUSS_BFESS',
      'STOKEN_BFESS',
      'BAIDUID_BFESS',
    };
    for (final host in [
      'www.baidu.com',
      'passport.baidu.com',
      'wappass.baidu.com',
      'tieba.baidu.com',
    ]) {
      for (final cookie in await cookies.getCookies(
        url: desktop.WebUri('https://$host/'),
      )) {
        if (allowed.contains(cookie.name)) {
          result[cookie.name] = '${cookie.value}';
        }
      }
    }
    return result;
  }
}

/// Callbacks stay platform neutral; Android keeps its existing WebView backend.
class NavigationDelegate {
  const NavigationDelegate({
    this.onNavigationRequest,
    this.onPageStarted,
    this.onPageFinished,
    this.onProgress,
    this.onWebResourceError,
    this.onHttpError,
  });
  final FutureOr<mobile.NavigationDecision> Function(mobile.NavigationRequest)?
  onNavigationRequest;
  final void Function(String)? onPageStarted, onPageFinished;
  final void Function(int)? onProgress;
  final void Function(mobile.WebResourceError)? onWebResourceError;
  final void Function(mobile.HttpResponseError)? onHttpError;

  mobile.NavigationDelegate get android => mobile.NavigationDelegate(
    onNavigationRequest: onNavigationRequest,
    onPageStarted: onPageStarted,
    onPageFinished: onPageFinished,
    onProgress: onProgress,
    onWebResourceError: onWebResourceError,
    onHttpError: onHttpError,
  );
}

class WebViewController {
  final mobile.WebViewController? _mobile = Platform.isWindows
      ? null
      : mobile.WebViewController();
  final _ready = Completer<desktop.InAppWebViewController>();
  NavigationDelegate? _delegate;
  String? _userAgent;
  bool _javascript = true;
  bool _disposed = false;
  Object? get platform => _mobile?.platform;

  Future<void> setJavaScriptMode(mobile.JavaScriptMode mode) async {
    if (_mobile != null) return _mobile.setJavaScriptMode(mode);
    _javascript = mode == mobile.JavaScriptMode.unrestricted;
  }

  Future<void> setNavigationDelegate(NavigationDelegate delegate) async {
    _delegate = delegate;
    if (_mobile != null) await _mobile.setNavigationDelegate(delegate.android);
  }

  Future<void> setUserAgent(String? value) async {
    if (_mobile != null) return _mobile.setUserAgent(value);
    _userAgent = value;
    if (_ready.isCompleted && !_disposed) {
      await (await _ready.future).setSettings(
        settings: desktop.InAppWebViewSettings(userAgent: value ?? ''),
      );
    }
  }

  Future<void> loadRequest(Uri uri) async {
    if (_mobile != null) return _mobile.loadRequest(uri);
    if (DesktopWebSession.initializationError != null || _disposed) return;
    final controller = await _ready.future;
    if (!_disposed) {
      await controller.loadUrl(
        urlRequest: desktop.URLRequest(url: desktop.WebUri.uri(uri)),
      );
    }
  }

  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    if (_mobile != null) return _mobile.loadHtmlString(html, baseUrl: baseUrl);
    if (DesktopWebSession.initializationError != null || _disposed) return;
    final controller = await _ready.future;
    if (!_disposed) {
      await controller.loadData(
        data: html,
        baseUrl: baseUrl == null ? null : desktop.WebUri(baseUrl),
      );
    }
  }

  Future<void> reload() async {
    if (_mobile != null) return _mobile.reload();
    if (DesktopWebSession.initializationError != null || _disposed) return;
    final controller = await _ready.future;
    if (!_disposed) await controller.reload();
  }

  Future<void> runJavaScript(String script) async {
    if (_mobile != null) return _mobile.runJavaScript(script);
    if (DesktopWebSession.initializationError != null || _disposed) return;
    final controller = await _ready.future;
    if (!_disposed) await controller.evaluateJavascript(source: script);
  }
}

class WebViewWidget extends StatefulWidget {
  const WebViewWidget({super.key, required this.controller});
  final WebViewController controller;
  @override
  State<WebViewWidget> createState() => _WebViewWidgetState();
}

class _WebViewWidgetState extends State<WebViewWidget> {
  @override
  void dispose() {
    if (Platform.isWindows) widget.controller._disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.controller;
    if (!Platform.isWindows) {
      return mobile.WebViewWidget(controller: owner._mobile!);
    }
    if (DesktopWebSession.initializationError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('内置浏览器无法启动，请安装 Microsoft Edge WebView2 后重启应用。'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://developer.microsoft.com/microsoft-edge/webview2/',
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('打开 WebView2 下载页'),
            ),
          ],
        ),
      );
    }
    return desktop.InAppWebView(
      webViewEnvironment: DesktopWebSession.environment,
      initialSettings: desktop.InAppWebViewSettings(
        javaScriptEnabled: owner._javascript,
        userAgent: owner._userAgent,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) async {
        await controller.setSettings(
          settings: desktop.InAppWebViewSettings(
            userAgent: owner._userAgent ?? '',
            javaScriptEnabled: owner._javascript,
          ),
        );
        owner._ready.complete(controller);
      },
      onLoadStart: (_, url) => owner._delegate?.onPageStarted?.call('$url'),
      onLoadStop: (_, url) => owner._delegate?.onPageFinished?.call('$url'),
      onProgressChanged: (_, progress) =>
          owner._delegate?.onProgress?.call(progress),
      shouldOverrideUrlLoading: (_, action) async {
        final url = action.request.url;
        if (url == null || url.toString() == 'about:blank') {
          return desktop.NavigationActionPolicy.ALLOW;
        }
        final decision = await owner._delegate?.onNavigationRequest?.call(
          mobile.NavigationRequest(
            url: '$url',
            isMainFrame: action.isForMainFrame,
          ),
        );
        return decision == mobile.NavigationDecision.prevent
            ? desktop.NavigationActionPolicy.CANCEL
            : desktop.NavigationActionPolicy.ALLOW;
      },
      onReceivedError: (_, request, error) =>
          owner._delegate?.onWebResourceError?.call(
            mobile.WebResourceError(
              errorCode: error.type.toNativeValue() ?? -1,
              description: error.description,
              isForMainFrame: request.isForMainFrame,
              url: request.url.toString(),
            ),
          ),
      onReceivedHttpError: (_, request, response) =>
          owner._delegate?.onHttpError?.call(
            mobile.HttpResponseError(
              request: mobile.WebResourceRequest(uri: request.url),
            ),
          ),
    );
  }
}

class WebViewCookieManager {
  final mobile.WebViewCookieManager? _mobile = Platform.isWindows
      ? null
      : mobile.WebViewCookieManager();
  Object? get platform => _mobile?.platform;
  Future<bool> clearCookies() =>
      _mobile?.clearCookies() ?? DesktopWebSession.cookies.deleteAllCookies();
  Future<void> setCookie(mobile.WebViewCookie cookie) async {
    if (_mobile != null) return _mobile.setCookie(cookie);
    final saved = await DesktopWebSession.cookies.setCookie(
      url: desktop.WebUri('https://tieba.baidu.com/'),
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      isSecure: true,
      isHttpOnly:
          cookie.name.startsWith('BDUSS') || cookie.name.startsWith('STOKEN'),
    );
    if (!saved) throw StateError('无法同步网页登录状态');
  }
}
