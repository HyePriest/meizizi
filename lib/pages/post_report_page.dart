import 'dart:async';

import 'package:flutter/material.dart';
import '../data/app_webview.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';

class PostReportPage extends StatefulWidget {
  const PostReportPage({
    super.key,
    required this.threadId,
    required this.postId,
    required this.commentId,
    required this.title,
  });
  final String threadId, postId, commentId, title;

  @override
  State<PostReportPage> createState() => _PostReportPageState();
}

class _PostReportPageState extends State<PostReportPage> {
  late final String _account;
  late final WebViewController _controller;
  final _api = TiebaApi();
  final _upgraded = <String>{};
  final _documentLoads = <String, List<DateTime>>{};
  bool _accountInvalid = false, _configured = false, _opening = false;
  bool _navigationStopped = false;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _account = AuthStore.instance.activeId;
    AuthStore.instance.addListener(_accountChanged);
    _controller = WebViewController();
    unawaited(_configure());
  }

  Future<void> _configure() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted || _accountInvalid || _navigationStopped) return;
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            final now = DateTime.now();
            final loads = _documentLoads.putIfAbsent(
              '${uri.host}${uri.path}',
              () => [],
            );
            loads.removeWhere(
              (time) => now.difference(time) > const Duration(seconds: 20),
            );
            loads.add(now);
            if (loads.length >= 4) _stopNavigation();
          },
          onProgress: (value) {
            if (mounted && !_accountInvalid) setState(() => _progress = value);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '举报页面加载失败，请重试');
            }
          },
          onHttpError: (error) {
            if (mounted && error.request?.uri.path == '/complaint/info') {
              setState(() => _error = '举报页面暂不可用，请稍后重试');
            }
          },
          onNavigationRequest: (request) {
            if (_accountInvalid || _navigationStopped) {
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                !(uri.host == 'baidu.com' || uri.host.endsWith('.baidu.com'))) {
              return NavigationDecision.prevent;
            }
            if (uri.scheme == 'http') {
              if (!_upgraded.add(uri.toString())) {
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
      if (!mounted || _accountInvalid) return;
      setState(() => _configured = true);
      await _open();
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开举报页面，请重新进入');
    }
  }

  Future<void> _open() async {
    if (_accountInvalid || !_configured || _opening) return;
    _opening = true;
    _navigationStopped = false;
    setState(() {
      _error = null;
      _progress = 0;
    });
    _upgraded.clear();
    _documentLoads.clear();
    try {
      if (![
        widget.threadId,
        widget.postId,
        widget.commentId,
      ].every((id) => RegExp(r'^\d+$').hasMatch(id))) {
        throw const FormatException();
      }
      // The checkjubao endpoint supplies the current form, including its token
      // and the target post. Legacy /complaint/info can redirect in a loop.
      final uri = await _api.reportUrl(
        widget.commentId == '0' ? widget.postId : widget.commentId,
      );
      await AuthStore.instance.syncWebSession();
      if (!mounted || _accountInvalid) return;
      // Open the form only. Reasons, verification and submission stay in the user's hands.
      await _controller.loadRequest(uri);
    } catch (e) {
      if (mounted && !_accountInvalid) {
        setState(
          () => _error = e is TiebaException ? e.message : '举报页面加载失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _stopNavigation() {
    if (!mounted || _navigationStopped) return;
    _navigationStopped = true;
    unawaited(_controller.runJavaScript('window.stop();').catchError((_) {}));
    setState(() {
      _progress = 100;
      _error = '举报页面重复跳转，点击重试可重新获取入口';
    });
  }

  void _accountChanged() {
    if (!mounted || _account == AuthStore.instance.activeId) return;
    _accountInvalid = true;
    _api.close();
    unawaited(_controller.loadHtmlString('<html><body></body></html>'));
    setState(() => _error = '账号已切换，请重新打开举报页面');
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: _accountInvalid || !_configured || _opening ? null : _open,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_progress < 100 && _error == null)
            LinearProgressIndicator(value: _progress / 100),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        if (!_accountInvalid) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _opening ? null : _open,
                            child: const Text('重试'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
