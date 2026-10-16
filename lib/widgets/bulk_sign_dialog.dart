import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import 'forum_widgets.dart';

class BulkSignTask extends ChangeNotifier {
  BulkSignTask._();
  static final instance = BulkSignTask._();
  late TiebaApi _api;
  bool _running = false,
      _cancelled = false,
      _finished = false,
      _allSigned = false;
  String _identity = "";
  DateTime? _startedDay;
  bool get finished =>
      _identity == AuthStore.instance.activeId &&
      _finished &&
      _startedDay == DateUtils.dateOnly(DateTime.now());
  bool get allSigned => finished && _allSigned;
  int _total = 0, _completed = 0, _success = 0, _unavailable = 0;
  int get unavailable => _unavailable;
  String get buttonLabel => running
      ? '签到中…'
      : !finished
      ? '一键签到'
      : allSigned
      ? (_unavailable > 0 ? '签到完成' : '已全部签到')
      : '部分未完成';
  String get summary =>
      '$_status · 已签 $_success / $_total 个吧'
      '${_unavailable > 0 ? '，跳过 $_unavailable 个无法签到的吧' : ''}'
      '${!_allSigned && _total > _success + _unavailable ? '，${_total - _success - _unavailable} 个未完成' : ''}';
  String _status = '正在读取关注的吧…';
  final List<String> _results = [];
  bool get running => _running;
  String get status => _status;
  int get completed => _completed;
  int get total => _total;
  int get success => _success;
  List<String> get results => List.unmodifiable(_results);
  void stop() {
    _cancelled = true;
    _status = '正在结束当前请求…';
    notifyListeners();
  }

  Future<void> start() async {
    if (_running) return;
    _api = TiebaApi();
    _identity = AuthStore.instance.activeId;
    _startedDay = DateUtils.dateOnly(DateTime.now());
    _finished = false;
    _allSigned = false;
    _running = true;
    _cancelled = false;
    _total = _completed = _success = _unavailable = 0;
    _results.clear();
    _status = '正在读取关注的吧…';
    notifyListeners();
    await _run();
    _api.close();
  }

  void _update(VoidCallback callback) {
    callback();
    notifyListeners();
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
              final unavailable =
                  !already &&
                  !e.uncertain &&
                  unavailableForumMessage(e.message);
              if (already) {
                await LocalStore.instance.markForumSigned(identity, name);
              }
              _update(() {
                _completed++;
                if (already) _success++;
                if (unavailable) _unavailable++;
                _results.add(
                  '$name吧：${unavailable
                      ? '无法签到，已跳过（${e.message}）'
                      : e.uncertain
                      ? '结果未确认，请进入吧页面核对'
                      : e.message}',
                );
              });
              if (!already &&
                  !unavailable &&
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
      _allSigned =
          !_cancelled &&
          stopped == null &&
          AuthStore.instance.activeId == identity &&
          _success + _unavailable == _total;
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
      _allSigned = false;
      _update(
        () => _status = e is TiebaException ? e.message : '签到中断，请检查网络后再试',
      );
    } finally {
      _update(() {
        _running = false;
        _finished = true;
      });
    }
  }
}
