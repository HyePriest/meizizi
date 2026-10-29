import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/share_content.dart';
import '../data/tieba_api.dart';
import '../widgets/app_snack_bar.dart';

class ForumPosterPage extends StatefulWidget {
  const ForumPosterPage({super.key, required this.content});
  final ShareContent content;

  @override
  State<ForumPosterPage> createState() => _ForumPosterPageState();
}

class _ForumPosterPageState extends State<ForumPosterPage> {
  late Future<Uint8List> _poster = _render();

  Future<Uint8List> _render() async {
    final summary = await TiebaApi.forumSummary(widget.content.forum);
    return widget.content.renderPoster(headerImage: forumCoverUrl(summary));
  }

  bool _sharing = false;

  Future<void> _share(Uint8List bytes) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await ShareContent.channel.invokeMethod<void>('shareImage', {
        'bytes': bytes,
        'title': widget.content.title,
        'url': widget.content.url,
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('未能打开分享窗口，请重试')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('吧分享海报')),
    body: FutureBuilder<Uint8List>(
      future: _poster,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null)
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : () => _share(bytes),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(
                        Platform.isWindows
                            ? (_sharing ? '正在保存' : '保存海报')
                            : (_sharing ? '正在打开分享' : '分享海报'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        if (snapshot.hasError)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('海报生成失败，请重试'),
                TextButton(
                  onPressed: () => setState(() => _poster = _render()),
                  child: const Text('重新制作'),
                ),
              ],
            ),
          );
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在制作海报…'),
            ],
          ),
        );
      },
    ),
  );
}
