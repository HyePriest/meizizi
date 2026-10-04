import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import 'login_page.dart';

class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    required this.threadId,
    required this.forumName,
    required this.forumId,
    required this.title,
    this.postId,
    this.replyUid,
  });
  final String threadId, forumName, forumId, title;
  final String? postId, replyUid;
  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  final _controller = TextEditingController();
  final _api = TiebaApi();
  late final Future<SharedPreferences> _prefs;
  Timer? _saveTimer;
  bool _busy = false, _sent = false, _uncertain = false;
  String? _error;
  String get _key =>
      'reply_draft_${widget.threadId}_${widget.postId ?? 'thread'}';
  @override
  void initState() {
    super.initState();
    _prefs = SharedPreferences.getInstance();
    _restore();
    _controller.addListener(() {
      _saveTimer?.cancel();
      _saveTimer = Timer(
        const Duration(milliseconds: 400),
        () => _save(_controller.text),
      );
    });
  }

  Future<void> _restore() async {
    final prefs = await _prefs;
    if (mounted && _controller.text.isEmpty) {
      _controller.text = prefs.getString(_key) ?? '';
    }
  }

  Future<void> _save(String value) async {
    if (_sent) return;
    try {
      final prefs = await _prefs;
      if (_sent) return;
      if (value.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, value);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_sent) _save(_controller.text);
    _controller.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _uncertain) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先输入回复内容');
      return;
    }
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _save(text);
    try {
      await _api.reply(
        threadId: widget.threadId,
        forumName: widget.forumName,
        forumId: widget.forumId,
        content: text,
        postId: widget.postId,
        replyUid: widget.replyUid,
      );
      _sent = true;
      _saveTimer?.cancel();
      try {
        await (await _prefs).remove(_key);
      } catch (_) {}
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is TiebaException ? e.message : '网络请求失败，草稿已保留';
          _uncertain = e is TiebaException && e.uncertain;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('写回复'),
        actions: [
          TextButton(
            onPressed: _busy || _uncertain ? null : _send,
            child: Text(_busy ? '发送中…' : '发送'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: AuthStore.instance,
            builder: (_, _) => Text(
              AuthStore.instance.isLoggedIn
                  ? '以 ${author(AuthStore.instance.user)} 的身份回复'
                  : '发送前需要登录百度账号',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_busy,
            minLines: 8,
            maxLines: 20,
            maxLength: 10000,
            decoration: const InputDecoration(
              hintText: '写下你的回复…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('未发送的内容会保存在本机。'),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (_uncertain)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('返回帖子核对结果'),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LoginPage(
                          verificationUrl:
                              'https://tieba.baidu.com/p/${widget.threadId}',
                        ),
                      ),
                    ),
              child: const Text('打开官方页面处理验证'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                      if (mounted) setState(() {});
                    },
              child: const Text('重新登录'),
            ),
          ],
        ],
      ),
    ),
  );
}
