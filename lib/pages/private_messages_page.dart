import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth_store.dart';
import '../data/models.dart';
import '../data/private_messages.dart';
import '../widgets/post_widgets.dart';
import '../widgets/voice_player.dart';
import '../widgets/app_snack_bar.dart';
import 'image_page.dart';
import 'login_page.dart';
import 'private_messages_web_page.dart';

class PrivateMessagesPage extends StatefulWidget {
  const PrivateMessagesPage({super.key});
  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  late PrivateMessagesApi _api;
  final _items = <Json>[];
  bool _busy = false, _more = true, _retryReset = true;
  int _offset = 0, _revision = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _api = PrivateMessagesApi();
    AuthStore.instance.addListener(_accountChanged);
    _load(reset: true);
  }

  void _accountChanged() {
    if (_api.account == AuthStore.instance.activeId) return;
    _revision++;
    _api.close();
    _api = PrivateMessagesApi();
    setState(() {
      _items.clear();
      _busy = false;
      _offset = 0;
    });
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    if (!AuthStore.instance.isLoggedIn) {
      setState(() {
        _error = '登录后查看私信';
        _more = false;
      });
      return;
    }
    final revision = ++_revision;
    _retryReset = reset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.contacts(reset ? 0 : _offset);
      if (!mounted || revision != _revision) return;
      setState(() {
        if (reset) {
          _items.clear();
          _offset = 0;
        }
        final seen = _items.map((m) => '${m['uid']}').toSet();
        _items.addAll(result.items.where((m) => seen.add('${m['uid']}')));
        _offset += result.pageSize;
        _more = result.more;
      });
    } catch (e) {
      if (mounted && revision == _revision)
        setState(() => _error = e is TiebaException ? e.message : '私信加载失败，请重试');
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
    if (mounted && !_busy) _load(reset: true);
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
      title: const Text('私信'),
      actions: [
        IconButton(
          tooltip: '重新登录',
          onPressed: _login,
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: _busy ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length)
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: AuthStore.instance.isLoggedIn
                          ? () => _load(reset: _retryReset)
                          : _login,
                      child: Text(AuthStore.instance.isLoggedIn ? '重试' : '登录'),
                    ),
                  ] else if (_more)
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('加载更多'),
                    )
                  else
                    Text(_items.isEmpty ? '暂无私信' : '已显示全部联系人'),
                ],
              ),
            );
          final item = _items[index];
          final name = firstText([
            item['show_nickname'],
            item['uname'],
            item['name_show'],
            item['nickname'],
          ], '吧友');
          final unread = number(item['unread']);
          return ListTile(
            leading: UserAvatar(user: {'portrait': item['portrait']}, size: 44),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(unread > 0 ? '$unread 条未读消息' : '查看聊天记录'),
            trailing: unread > 0
                ? Badge(label: Text(unread > 99 ? '99+' : '$unread'))
                : const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _PrivateChatPage(contact: item),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PrivateChatPage extends StatefulWidget {
  const _PrivateChatPage({required this.contact});
  final Json contact;
  @override
  State<_PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<_PrivateChatPage> {
  final _api = PrivateMessagesApi();
  final _messages = <Json>[];
  bool _busy = false, _more = true, _invalid = false, _retryOlder = false;
  String? _error;
  String get _uid => '${widget.contact['uid']}';
  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (_api.account == AuthStore.instance.activeId || !mounted) return;
    setState(() {
      _invalid = true;
      _messages.clear();
      _busy = false;
      _error = '账号已切换，请重新打开聊天';
    });
    _api.close();
  }

  Future<void> _load({bool older = false}) async {
    if (_busy || _invalid) return;
    _retryOlder = older;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final incoming = await _api.messages(
        _uid,
        before: older && _messages.isNotEmpty
            ? '${_messages.last['msgId']}'
            : '0',
      );
      if (!mounted || _invalid) return;
      setState(() {
        final merged = <String, Json>{
          for (final m in _messages) '${m['msgId']}': m,
        };
        final before = merged.length;
        for (final m in incoming) {
          merged['${m['msgId']}'] = m;
        }
        _messages
          ..clear()
          ..addAll(merged.values)
          ..sort((a, b) => number(b['msgId']).compareTo(number(a['msgId'])));
        if (older || before == 0)
          _more = incoming.isNotEmpty && merged.length > before;
      });
    } catch (e) {
      if (mounted && !_invalid)
        setState(
          () => _error = e is TiebaException ? e.message : '聊天记录加载失败，请重试',
        );
    } finally {
      if (mounted && !_invalid) setState(() => _busy = false);
    }
  }

  dynamic _decodeContent(dynamic value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {}
    try {
      return jsonDecode(plainText(value));
    } catch (_) {
      return null;
    }
  }

  Widget _content(Json message) {
    final type = number(message['msgType']), raw = message['content'];
    if (type == 1 || type == 0)
      return PostContent(
        parts: contentParts(raw),
        textStyle: const TextStyle(fontSize: 16, height: 1.45),
      );
    final decoded = _decodeContent(raw);
    final parts = decoded is List ? objects(decoded) : [object(decoded)];
    if (type == 2 || type == 4) {
      final urls = parts
          .map((p) => firstText([p['big_src'], p['src'], p['url_d']]))
          .where((s) => s.isNotEmpty)
          .map(
            (s) =>
                s.startsWith('http://') ? s.replaceFirst('http:', 'https:') : s,
          )
          .toList();
      if (urls.isNotEmpty)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final url in urls)
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImagePage(url: url, urls: urls),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 210,
                      fit: BoxFit.contain,
                      cacheWidth: 640,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('图片加载失败，点击查看'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      return const Text('[表情或图片]');
    }
    if (type == 3 && parts.isNotEmpty && parts.first['voice_md5'] != null)
      return VoicePlayer(
        part: {
          ...parts.first,
          'during_time':
              ((double.tryParse('${parts.first['during_time']}') ?? 0) * 1000)
                  .round(),
        },
      );
    if (type == 11)
      return Text(firstText([object(decoded)['userMsg']], '系统消息'));
    return const Text('此消息类型请在官方私信中查看');
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
      title: Text(
        firstText([
          widget.contact['show_nickname'],
          widget.contact['uname'],
          widget.contact['name_show'],
        ], '聊天'),
      ),
      actions: [
        IconButton(
          tooltip: '官方网页',
          onPressed: _invalid
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PrivateMessagesWebPage(chatUid: _uid),
                  ),
                ),
          icon: const Icon(Icons.language),
        ),
        IconButton(
          tooltip: '刷新消息',
          onPressed: _busy || _invalid ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              if (!_invalid)
                TextButton(
                  onPressed: _busy ? null : () => _load(older: _retryOlder),
                  child: const Text('重试'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                ),
            ],
          ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _messages.isEmpty && !_busy && _error == null
              ? const Center(child: Text('暂无聊天记录'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _messages.length)
                      return _more && !_invalid
                          ? Center(
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _load(older: true),
                                child: const Text('查看更早消息'),
                              ),
                            )
                          : const SizedBox(height: 8);
                    final message = _messages[index];
                    final mine = '${message['fromUid']}' != _uid;
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .8,
                        ),
                        child: Column(
                          crossAxisAlignment: mine
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 4,
                              ),
                              child: Text(
                                fullDate(message['createTime']),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: _content(message),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _invalid
                    ? null
                    : () async {
                        try {
                          await const MethodChannel('com.jknl.tieba/session')
                              .invokeMethod('openOfficialTieba');
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showAppSnackBar(
                              const AppSnackBar(
                                content: Text('暂不支持在本应用发送私信，请使用官方贴吧客户端'),
                              ),
                            );
                        }
                      },
                icon: const Icon(Icons.open_in_new),
                label: const Text('发送消息请打开官方贴吧'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
