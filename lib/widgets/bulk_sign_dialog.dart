import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import 'forum_widgets.dart';

class BulkSignDialog extends StatefulWidget {
  const BulkSignDialog({super.key});
  @override
  State<BulkSignDialog> createState() => _BulkSignDialogState();
}

class _BulkSignDialogState extends State<BulkSignDialog> {
  final _api = TiebaApi();
  bool _running = true, _cancelled = false;
  int _total = 0, _completed = 0, _success = 0;
  String _status = '正在读取关注的吧…';
  final List<String> _results = [];
  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    _api.close();
    super.dispose();
  }

  void _update(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> _run() async {
    final identity = AuthStore.instance.activeId;
    final forums = <Json>[];
    final names = <String>{};
    try {
      for (var page = 1; ; page++) {
        if (_cancelled) break;
        if (AuthStore.instance.activeId != identity) {
          throw const TiebaException('账号已切换，签到已停止');
        }
        final result = await _api.followedForums(page);
        final incoming = result.items
            .where((f) => forumName(f).isNotEmpty && names.add(forumName(f)))
            .toList();
        forums.addAll(incoming);
        if (!result.hasMore) break;
        if (incoming.isEmpty || page >= 100) {
          throw const TiebaException('关注列表分页异常，未执行签到，请刷新后再试');
        }
      }
      _update(() => _total = forums.length);
      final pending = <Json>[];
      for (final forum in forums) {
        final name = forumName(forum);
        if (flag(forum['is_sign_in']) ||
            LocalStore.instance.forumSigned(identity, name)) {
          await LocalStore.instance.markForumSigned(identity, name);
          _update(() {
            _completed++;
            _success++;
            _results.add('$name吧：今天已签到，已跳过');
          });
        } else {
          pending.add(forum);
        }
      }
      var next = 0;
      String? stopped;
      if (!_cancelled && pending.isNotEmpty) {
        final session = await _api.prepareSignSession();
        Future<void> worker() async {
          while (!_cancelled && stopped == null && next < pending.length) {
            if (AuthStore.instance.activeId != identity) {
              stopped = '账号已切换，签到已停止';
              break;
            }
            final name = forumName(pending[next++]);
            _update(() => _status = '正在签到：$name吧');
            try {
              await _api.signForum(name, session: session);
              await LocalStore.instance.markForumSigned(identity, name);
              _update(() {
                _success++;
                _completed++;
                _results.add('$name吧：签到成功');
              });
            } catch (error) {
              final e = error is TiebaException
                  ? error
                  : const TiebaException('签到结果未确认，请核对', uncertain: true);
              final already =
                  e.message.contains('已签到') || e.message.contains('已经签到');
              if (already) {
                await LocalStore.instance.markForumSigned(identity, name);
              }
              _update(() {
                _completed++;
                if (already) _success++;
                _results.add(
                  '$name吧：${e.uncertain ? '结果未确认，请进入吧页面核对' : e.message}',
                );
              });
              if (!already &&
                  (e.uncertain ||
                      [
                        '登录',
                        '验证码',
                        '验证',
                        '风控',
                        '频繁',
                        '账号',
                      ].any(e.message.contains))) {
                stopped = '签到已停止：${e.message}';
              }
            }
          }
        }

        await worker();
      }
      _update(
        () => _status =
            stopped ??
            (_cancelled
                ? '已停止，未开始的吧未执行签到'
                : _total == 0
                ? '没有已关注的吧'
                : '签到完成'),
      );
    } catch (e) {
      _update(
        () => _status = e is TiebaException ? e.message : '签到中断，请检查网络后再试',
      );
    } finally {
      _update(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: AlertDialog(
      title: const Text('一键签到'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 12),
            if (_running)
              LinearProgressIndicator(
                value: _total > 0 ? _completed / _total : null,
              ),
            const SizedBox(height: 8),
            Text('已处理 $_completed / $_total · 成功或已签到 $_success'),
            if (_results.isNotEmpty)
              SizedBox(
                height: 220,
                child: ListView(
                  children: _results
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(r),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running
              ? (_cancelled
                    ? null
                    : () => _update(() {
                        _cancelled = true;
                        _status = '正在结束当前请求…';
                      }))
              : () => Navigator.of(context).pop(),
          child: Text(_running ? '停止' : '完成'),
        ),
      ],
    ),
  );
}
