import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../features/reading/reading_controller.dart';
import '../widgets/forum_header_card.dart';
import '../widgets/post_widgets.dart';
import 'user_page.dart';

class ForumDetailsPage extends StatefulWidget {
  const ForumDetailsPage({
    super.key,
    required this.name,
    required this.reader,
    required this.onFollow,
    required this.onRefresh,
    this.api,
  });
  final String name;
  final ReadingController reader;
  final Future<void> Function(bool followed) onFollow;
  final Future<void> Function() onRefresh;
  final TiebaApi? api;

  @override
  State<ForumDetailsPage> createState() => _ForumDetailsPageState();
}

class _ForumDetailsPageState extends State<ForumDetailsPage> {
  late final _api = widget.api ?? TiebaApi();
  Json _levels = {}, _rules = {};
  List<Json> _moderators = [];
  bool _loadingLevels = true, _loadingRules = true, _loadingModerators = true;
  String? _levelError, _ruleError, _moderatorError;
  int _generation = 0;
  String _loadedForumId = '';
  Json get _forum => widget.reader.data.forum;
  bool get _followed =>
      AuthStore.instance.isLoggedIn && widget.reader.forumFollowed;

  @override
  void initState() {
    super.initState();
    AuthStore.instance.addListener(_accountChanged);
    widget.reader.addListener(_readerChanged);
    _load();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _levels = {};
      _loadedForumId = '';
    });
    _load();
  }

  void _readerChanged() {
    final id = firstText([_forum['id']]);
    if (mounted && id.isNotEmpty && id != _loadedForumId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final account = AuthStore.instance.activeId;
    final id = firstText([_forum['id']]);
    _loadedForumId = id;
    if (id.isEmpty) {
      setState(() {
        _loadingLevels = _loadingRules = _loadingModerators = false;
        _levelError = _ruleError = _moderatorError = '吧信息尚未加载，请返回主页刷新后再试';
      });
      return;
    }
    bool valid() =>
        mounted &&
        generation == _generation &&
        account == AuthStore.instance.activeId;
    setState(() {
      _loadingLevels = _loadingRules = _loadingModerators = true;
      _levelError = _ruleError = _moderatorError = null;
    });
    await Future.wait([
      () async {
        try {
          final levels = await _api.forumLevels(id);
          if (valid()) setState(() => _levels = levels);
        } catch (_) {
          if (valid()) setState(() => _levelError = '等级资料加载失败');
        } finally {
          if (valid()) setState(() => _loadingLevels = false);
        }
      }(),
      () async {
        try {
          final rules = await _api.forumRules(id);
          if (valid()) setState(() => _rules = rules);
        } catch (_) {
          if (valid()) setState(() => _ruleError = '吧规加载失败');
        } finally {
          if (valid()) setState(() => _loadingRules = false);
        }
      }(),
      () async {
        try {
          final moderators = await _api.forumModerators(id);
          if (valid()) setState(() => _moderators = moderators);
        } catch (_) {
          if (valid()) setState(() => _moderatorError = '吧务名单加载失败');
        } finally {
          if (valid()) setState(() => _loadingModerators = false);
        }
      }(),
    ]);
  }

  Future<void> _follow() async {
    if (widget.reader.forumActionsBusy || widget.reader.forumFollowUncertain) {
      return;
    }
    final account = AuthStore.instance.activeId;
    final followed = _followed;
    if (followed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('取消关注？'),
          content: Text('确定不再关注${widget.name}吧吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('保留关注'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('取消关注'),
            ),
          ],
        ),
      );
      if (confirm != true ||
          !mounted ||
          account != AuthStore.instance.activeId ||
          _followed != followed ||
          widget.reader.forumActionsBusy ||
          widget.reader.forumFollowUncertain) {
        return;
      }
    }
    await widget.onFollow(!followed);
  }

  @override
  void dispose() {
    AuthStore.instance.removeListener(_accountChanged);
    widget.reader.removeListener(_readerChanged);
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(top: 12),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _error(String message) => Row(
    children: [
      Expanded(child: Text(message)),
      TextButton(onPressed: _load, child: const Text('重试')),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.reader, AuthStore.instance]),
    builder: (context, _) {
      final user = object(widget.reader.data.result?.data['user']);
      final member = object(_levels['user_info']);
      final level =
          [
            _forum['level_id'],
            _forum['user_level'],
            user['level_id'],
            member['level_id'],
            _levels['level_id'],
            _levels['user_level'],
          ].map(number).where((n) => n > 0).firstOrNull ??
          0;
      final names = {
        for (final item in objects(_levels['level_info']))
          number(item['id']): firstText([item['name']]),
      };
      final levelUser = <String, dynamic>{
        'level_id': level,
        'level_name': firstText([
          _forum['level_name'],
          user['level_name'],
          member['level_name'],
          _levels['level_name'],
          names[level],
        ]),
      };
      final scoreRaw = [
        _forum['cur_score'],
        user['cur_score'],
        member['cur_score'],
      ].where((value) => value != null && '$value'.isNotEmpty).firstOrNull;
      final score = number(scoreRaw);
      final next = number(_forum['levelup_score']) > score
          ? number(_forum['levelup_score'])
          : objects(_levels['level_info'])
                    .where((item) => number(item['id']) == level + 1)
                    .map((item) => number(item['score']))
                    .firstOrNull ??
                0;
      final floor =
          objects(_levels['level_info'])
              .where((item) => number(item['id']) == level)
              .map((item) => number(item['score']))
              .firstOrNull ??
          0;
      final rulesAvailable =
          objects(_rules['rules']).isNotEmpty ||
          firstText([_rules['preface']]).isNotEmpty;
      return Scaffold(
        appBar: AppBar(title: const Text('吧的更多内容')),
        body: RefreshIndicator(
          onRefresh: () async {
            await widget.onRefresh();
            if (mounted) await _load();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              ForumHeaderCard(
                forum: _forum,
                name: widget.name,
                level: _followed ? levelUser : {},
                levelNames: names,
                trailing: FilledButton.tonal(
                  onPressed:
                      widget.reader.forumActionsBusy || _forum['id'] == null
                      ? null
                      : widget.reader.forumFollowUncertain
                      ? widget.onRefresh
                      : _follow,
                  child: Text(
                    widget.reader.forumActionsBusy
                        ? '处理中'
                        : _followed
                        ? '已关注'
                        : '关注',
                  ),
                ),
              ),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('吧简介', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    SelectableText(forumDescription(_forum)),
                  ],
                ),
              ),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.rule_outlined),
                      title: const Text('吧规'),
                      subtitle: Text(
                        _loadingRules
                            ? '加载中…'
                            : _ruleError != null
                            ? '暂未取得吧规'
                            : firstText([_rules['title']], '本吧暂未设置吧规'),
                      ),
                      trailing: rulesAvailable
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: rulesAvailable
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ForumRulePage(rules: _rules),
                              ),
                            )
                          : null,
                    ),
                    if (_ruleError != null) _error(_ruleError!),
                  ],
                ),
              ),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '我的等级',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        if (_followed)
                          ForumLevelBadge(user: levelUser, levelNames: names),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!AuthStore.instance.isLoggedIn)
                      const Text('登录后查看等级和经验')
                    else if (!_followed)
                      const Text('关注后查看本吧等级和经验')
                    else if (_loadingLevels)
                      const Text('加载中…')
                    else if (_levelError != null)
                      _error(_levelError!)
                    else if (scoreRaw == null)
                      const Text('暂未取得经验数据，请下拉刷新')
                    else ...[
                      Text(next > score ? '经验 $score / $next' : '经验 $score'),
                      if (next > floor) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: ((score - floor) / (next - floor)).clamp(
                            0.0,
                            1.0,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '距下一级还需 ${next - score} 经验',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              _card(
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '吧务管理${_moderators.isEmpty ? '' : ' · ${_moderators.length}'}',
                  ),
                  children: [
                    if (_loadingModerators)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('加载中…'),
                      ),
                    if (_moderatorError != null) _error(_moderatorError!),
                    if (!_loadingModerators &&
                        _moderatorError == null &&
                        _moderators.isEmpty)
                      const Text('暂无吧务名单'),
                    for (final user in _moderators)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(user: user),
                        title: Text(author(user)),
                        trailing: ForumRoleBadge(user: user),
                        onTap: () => openUser(context, user),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ForumRulePage extends StatelessWidget {
  const ForumRulePage({super.key, required this.rules});
  final Json rules;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('吧规')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          firstText([rules['title']], '吧规'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (firstText([rules['preface']]).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: SelectableText('${rules['preface']}'),
          ),
        for (final rule in objects(rules['rules'])) ...[
          const SizedBox(height: 16),
          Text(
            firstText([rule['title']]),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          PostContent(parts: contentParts(rule['content'])),
        ],
        const SizedBox(height: 24),
      ],
    ),
  );
}
