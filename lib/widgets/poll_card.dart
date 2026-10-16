import 'package:flutter/material.dart';

import 'dart:async';

import '../data/models.dart';

class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.onVote,
    required this.onRefresh,
    this.hasVoted = false,
  });
  final Json poll;
  final Future<bool> Function(List<int>) onVote;
  final FutureOr<void> Function() onRefresh;
  final bool hasVoted;
  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final _selected = <int>{};
  @override
  void initState() {
    super.initState();
    if (flag(widget.poll['is_polled'])) {
      _selected.addAll(
        '${widget.poll['polled_value'] ?? ''}'
            .split(',')
            .map(number)
            .where((id) => id > 0),
      );
    }
  }

  bool _busy = false, _confirmed = false, _uncertain = false;
  bool _showResults = false, _refreshing = false;
  String? _error;
  bool get _multi => number(widget.poll['is_multi']) > 0;
  bool get _voted =>
      widget.hasVoted ||
      _confirmed ||
      flag(widget.poll['is_polled']) ||
      flag(widget.poll['is_poll']) ||
      flag(widget.poll['is_voted']) ||
      flag(widget.poll['has_vote']);
  bool get _ended {
    final end = number(widget.poll['end_time'] ?? widget.poll['expire_time']);
    return flag(widget.poll['is_end']) ||
        (end > 0 &&
            DateTime.now().millisecondsSinceEpoch >=
                (end < 100000000000 ? end * 1000 : end));
  }

  Future<void> _submit() async {
    if (_busy || _voted || _ended || _uncertain || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final success = await widget.onVote(_selected.toList()..sort());
      if (!mounted) return;
      if (success) {
        setState(() {
          _confirmed = true;
          _showResults = true;
        });
        await _refreshResults();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uncertain = e is TiebaException && e.uncertain;
          _error = e is TiebaException ? e.message : '投票失败，请稍后重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshResults() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await widget.onRefresh();
      if (mounted) setState(() => _showResults = true);
    } catch (_) {
      if (mounted)
        setState(() => _error = _voted ? '已投票，票数刷新失败，请稍后刷新' : '票数加载失败，请重试');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = objects(widget.poll['options']);
    if (options.isEmpty) return const SizedBox.shrink();
    final total = number(widget.poll['total_poll']);
    final users = number(widget.poll['total_num']);
    final showResults = _showResults || _voted;
    final enabled = !_busy && !_refreshing && !_voted && !_ended && !_uncertain;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstText([widget.poll['title']], '投票'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${_multi ? '多选' : '单选'}${showResults ? ' · $users 人参与 · $total 票' : ''}',
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < options.length; index++)
            Builder(
              builder: (context) {
                final option = options[index];
                // The submission protocol numbers options from 1.
                final id = number(option['id']) > 0
                    ? number(option['id'])
                    : index + 1;
                final votes = number(option['num'] ?? option['vote_num']);
                final percent = total > 0
                    ? (votes * 100 / total).toStringAsFixed(1)
                    : '0';
                final selected = _selected.contains(id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _multi
                        ? (selected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank)
                        : (selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plainText(option['text'])),
                      if (httpsImage(option['image']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Image.network(
                            httpsImage(option['image']),
                            height: 100,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                  subtitle: showResults ? Text('$votes 票 · $percent%') : null,
                  onTap: enabled
                      ? () {
                          final max = number(widget.poll['max_num']);
                          if (_multi &&
                              !selected &&
                              max > 0 &&
                              _selected.length >= max) {
                            setState(() => _error = '最多选择 $max 项');
                            return;
                          }
                          setState(() {
                            _error = null;
                            if (!_multi) _selected.clear();
                            if (_multi && selected) {
                              _selected.remove(id);
                            } else {
                              _selected.add(id);
                            }
                          });
                        }
                      : null,
                );
              },
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Row(
            children: [
              FilledButton(
                onPressed: enabled && _selected.isNotEmpty ? _submit : null,
                child: Text(
                  _busy
                      ? '提交中…'
                      : _voted
                      ? '已投票'
                      : _ended
                      ? '投票已结束'
                      : '提交投票',
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy || _refreshing ? null : _refreshResults,
                child: Text(
                  _refreshing
                      ? '加载票数…'
                      : showResults
                      ? '刷新票数'
                      : '查看票数',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
