import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'dart:async';

import '../data/auth_store.dart';

/// Private conversations use Tieba's official web inbox and its own send UI.
class PrivateMessagesWebPage extends StatefulWidget {
  const PrivateMessagesWebPage({super.key, this.chatUid});
  final String? chatUid;
  @override
  State<PrivateMessagesWebPage> createState() => _PrivateMessagesWebPageState();
}

class _PrivateMessagesWebPageState extends State<PrivateMessagesWebPage> {
  late final String _account = AuthStore.instance.activeId;
  late final WebViewController _controller;
  late final Widget _webView;
  bool _configured = false, _opening = false, _accountInvalid = false;
  bool _navigationStopped = false;
  final _upgradedUrls = <String>{};
  final _documentLoads = <String, List<DateTime>>{};
  int _progress = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    _controller = WebViewController();
    _webView = WebViewWidget(
      key: ValueKey('private-inbox-$_account'),
      controller: _controller,
    );
    unawaited(_configure());
  }

  Future<void> _configure() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted || _accountInvalid || _navigationStopped) return;
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            final now = DateTime.now();
            final key = '${uri.host}${uri.path}';
            final loads = _documentLoads.putIfAbsent(key, () => []);
            loads.removeWhere(
              (time) => now.difference(time) > const Duration(seconds: 20),
            );
            loads.add(now);
            if (loads.length >= 4) _stopNavigation();
          },
          onPageFinished: (_) async {
            try {
              await _controller.runJavaScript(r"""
                (() => {
                  let meta = document.querySelector('meta[name=viewport]');
                  if (!meta) { meta=document.createElement('meta'); meta.name='viewport'; document.head.appendChild(meta); }
                  meta.content='width=device-width,initial-scale=1';
                  let css=document.getElementById('tieba-mobile-inbox');
                  if (!css) { css=document.createElement('style'); css.id='tieba-mobile-inbox'; document.head.appendChild(css); }
                  css.textContent='html,body{min-width:0!important;width:100%!important;overflow-x:hidden!important}.wrap2{display:block!important;width:100%!important;margin:0!important}.sixin423{width:100%!important;margin:0!important}.sixin423-left{width:30%!important}.sixin423-right{width:70%!important}.head,.head_inner,.search_main,.footer{display:none!important}';
                })();
              """);
            } catch (_) {}
          },
          onProgress: (value) {
            if (mounted && !_navigationStopped && _progress != value) {
              setState(() => _progress = value);
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '官方私信页面加载失败，请重新加载');
            }
          },
          onHttpError: (error) {
            if (mounted && error.request?.uri.path == '/im/pcmsg') {
              setState(() => _error = '官方私信页面暂不可用，请稍后重试');
            }
          },
          onNavigationRequest: (request) {
            if (_accountInvalid || _navigationStopped)
              return NavigationDecision.prevent;
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                !(uri.host == 'baidu.com' || uri.host.endsWith('.baidu.com'))) {
              return NavigationDecision.prevent;
            }
            // The main host's legacy inbox redirects HTTPS back to HTTP.
            // Its official c.tieba host serves the same inbox over HTTPS.
            if (uri.host == 'tieba.baidu.com' && uri.path.startsWith('/im/')) {
              if (!_upgradedUrls.add(uri.toString())) {
                _stopNavigation();
              } else {
                unawaited(
                  _controller.loadRequest(
                    uri.replace(scheme: 'https', host: 'c.tieba.baidu.com'),
                  ),
                );
              }
              return NavigationDecision.prevent;
            }
            if (uri.scheme == 'http') {
              if (!_upgradedUrls.add(uri.toString())) {
                _stopNavigation();
              } else {
                unawaited(
                  _controller.loadRequest(uri.replace(scheme: 'https')),
                );
              }
              return NavigationDecision.prevent;
            }
            return uri.scheme == 'https'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await AuthStore.instance.syncWebSession();
      if (!mounted || _account != AuthStore.instance.activeId) return;
      setState(() => _configured = true);
      await _open();
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开私信，请重新进入此页面');
    }
  }

  void _stopNavigation() {
    if (_navigationStopped || !mounted) return;
    _navigationStopped = true;
    unawaited(_controller.runJavaScript('window.stop();').catchError((_) {}));
    setState(() {
      _progress = 100;
      _error = '官方私信页发生重复跳转，已停止自动刷新。可点击重新加载。';
    });
  }

  void _accountChanged() {
    if (!mounted || _account == AuthStore.instance.activeId) return;
    _accountInvalid = true;
    _controller.loadHtmlString('<html><body></body></html>');
    setState(() {
      _progress = 100;
      _error = '账号已切换，请重新打开私信';
    });
  }

  Future<void> _open() async {
    if (_accountInvalid || !_configured || _opening) return;
    _opening = true;
    _navigationStopped = false;
    _upgradedUrls.clear();
    _documentLoads.clear();
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      if (!mounted || _account != AuthStore.instance.activeId) return;
      await _controller.loadRequest(
        Uri.https(
          'c.tieba.baidu.com',
          '/im/pcmsg',
          widget.chatUid == null ? null : {'from': widget.chatUid!},
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开私信，请重新加载');
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('私信'),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: _accountInvalid || !_configured ? null : _open,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _webView),
          if (_accountInvalid)
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).colorScheme.surface),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_progress < 100 && !_accountInvalid)
                  LinearProgressIndicator(value: _progress / 100),
                if (_error != null)
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
