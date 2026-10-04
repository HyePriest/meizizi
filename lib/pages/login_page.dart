import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.verificationUrl});
  final String? verificationUrl;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final WebViewController _controller;
  final _api = TiebaApi();
  int _progress = 0;
  bool _busy = false;
  String? _error;
  bool get _login => widget.verificationUrl == null;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '页面加载失败，请检查网络或重新加载');
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final host = uri?.host.toLowerCase() ?? '';
            if (uri == null ||
                !(host == 'baidu.com' || host.endsWith('.baidu.com'))) {
              return NavigationDecision.prevent;
            }
            if (uri.scheme == 'http') {
              _controller.loadRequest(uri.replace(scheme: 'https'));
              return NavigationDecision.prevent;
            }
            return uri.scheme == 'https'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          widget.verificationUrl ?? 'https://wappass.baidu.com/passport/?login&tpl=tb&u=https%3A%2F%2Ftieba.baidu.com%2F',
        ),
      );
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cookies = await AuthStore.instance.webCookies();
      await _api.acceptLogin(cookies);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is TiebaException ? e.message : '未能确认登录，请完成网页登录后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_login ? '百度账号登录' : '百度官方页面'),
      actions: [
        IconButton(
          onPressed: () {
            setState(() => _error = null);
            _controller.reload();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Expanded(child: WebViewWidget(controller: _controller)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  _login ? '在百度官方页面登录，完成后点击下方按钮。' : '在官方页面处理验证，完成后返回帖子核对结果。',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : _login
                      ? _confirm
                      : () => Navigator.of(context).pop(),
                  child: Text(
                    _busy
                        ? '确认登录中…'
                        : _login
                        ? '已完成登录，返回贴吧'
                        : '返回帖子',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
