import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/app_webview.dart';

import 'package:webview_flutter_android/webview_flutter_android.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url});
  final String url;
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _controller
              .runJavaScript(
                'document.querySelectorAll("video").forEach(v=>{if(!document.hidden)v.play().catch(()=>{});})',
              )
              .catchError((_) {}),
          onNavigationRequest: (request) =>
              ['https', 'http'].contains(Uri.tryParse(request.url)?.scheme)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '视频加载失败，请重试');
            }
          },
        ),
      );
    _configureAndLoad();
  }

  Future<void> _configureAndLoad() async {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }
    if (mounted) _load();
  }

  void _load() {
    final uri = Uri.parse(widget.url);
    if (RegExp(
      r'\.(mp4|m3u8|webm)$',
      caseSensitive: false,
    ).hasMatch(uri.path)) {
      final source = const HtmlEscape(HtmlEscapeMode.attribute)
          .convert(widget.url);
      _controller.loadHtmlString(
        '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;background:#000}video{width:100%;height:100vh}</style><video controls autoplay playsinline preload="auto" src="$source"></video>',
        baseUrl: 'https://tieba.baidu.com/',
      );
    } else {
      _controller.loadRequest(uri);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller
          .runJavaScript(
            'document.querySelectorAll("video,audio").forEach(v=>v.pause())',
          )
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.loadHtmlString('<html></html>').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('视频')),
    body: Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _load();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
