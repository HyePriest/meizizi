import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.verificationUrl});
  final String? verificationUrl;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Tencent's mobile page tries to launch QQ via app links. Use its official
  // desktop web flow so authorization can finish inside this WebView.
  static const _qqWebUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0.0.0 Safari/537.36';
  static final _baiduLoginUrl = Uri.parse(
    'https://wappass.baidu.com/passport/?login&tpl=tb&u=https%3A%2F%2Ftieba.baidu.com%2F',
  );
  static final _qqLoginUrl = Uri.https(
    'passport.baidu.com',
    '/phoenix/account/startlogin',
    {
      'type': '15',
      'tpl': 'tb',
      'u': 'https://tieba.baidu.com/',
      'display': 'page',
      'act': 'login',
    },
  );
  late final WebViewController _controller;
  final _api = TiebaApi();
  int _progress = 0;
  bool _busy = false;
  bool _qqLogin = false;
  String? _error;
  String? _loginStatus;
  bool get _login => widget.verificationUrl == null;
  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted || !_login || !_qqLogin) return;
            final uri = Uri.tryParse(url);
            final host = uri?.host.toLowerCase() ?? '';
            if (host == 'qq.com' || host.endsWith('.qq.com')) {
              setState(() => _loginStatus = '正在腾讯授权页，等待扫码或登录完成');
            } else if (host == 'baidu.com' || host.endsWith('.baidu.com')) {
              final returned =
                  uri?.path.contains('afterauth') == true ||
                  host == 'tieba.baidu.com';
              setState(
                () => _loginStatus = returned
                    ? '已返回百度，请完成页面提示，再点击「已完成登录，返回贴吧」'
                    : '正在打开百度 QQ 登录入口',
              );
            }
          },
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
            final baidu = host == 'baidu.com' || host.endsWith('.baidu.com');
            final qq = _login && (host == 'qq.com' || host.endsWith('.qq.com'));
            if (uri == null || !(baidu || qq)) {
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
        widget.verificationUrl == null
            ? _baiduLoginUrl
            : Uri.parse(widget.verificationUrl!),
      );
  }

  Future<void> _openLogin(bool qq) async {
    setState(() {
      _qqLogin = qq;
      _error = null;
      _loginStatus = qq ? '正在打开 QQ 登录' : null;
      _progress = 0;
    });
    try {
      final platform = _controller.platform;
      final cookies = WebViewCookieManager().platform;
      if (platform is AndroidWebViewController &&
          cookies is AndroidWebViewCookieManager) {
        // QQ's embedded login frame and the Baidu callback need cookies across
        // the authorization flow. Apply this only to this login WebView.
        await cookies.setAcceptThirdPartyCookies(platform, qq);
      }
      await _controller.setUserAgent(qq ? _qqWebUserAgent : null);
      if (!mounted) return;
      await _controller.loadRequest(qq ? _qqLoginUrl : _baiduLoginUrl);
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开登录页面，请重新选择登录方式');
    }
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
      if (_qqLogin &&
          (cookies['BDUSS'] ?? cookies['BDUSS_BFESS'] ?? '').isEmpty) {
        throw const TiebaException(
          '尚未收到百度登录状态。QQ 安全中心授权后，网页还需继续完成腾讯授权并返回百度；请查看网页是否仍在等待扫码或确认授权。',
        );
      }
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
        if (_login)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('百度登录')),
                ButtonSegment(value: true, label: Text('QQ 登录')),
              ],
              selected: {_qqLogin},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => _openLogin(selection.single),
            ),
          ),
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
                if (_loginStatus != null) ...[
                  Text(_loginStatus!),
                  const SizedBox(height: 8),
                ],
                Text(
                  _login
                      ? _qqLogin
                            ? '可截图后在 QQ 中扫码，也可选择密码登录。QQ 确认后回到此页面，继续完成网页上的授权，再点击下方按钮。'
                            : '在百度官方页面登录，完成后点击下方按钮。'
                      : '在官方页面处理验证，完成后返回帖子核对结果。',
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
