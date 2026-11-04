import 'package:flutter/material.dart';

import '../data/tieba_api.dart';

String feedCount(dynamic value) {
  final count = number(value);
  if (count < 10000) return '$count';
  return '${(count / 10000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}W';
}

class HomeForumStats extends StatelessWidget {
  const HomeForumStats({super.key, required this.forum});
  final Json forum;

  @override
  Widget build(BuildContext context) {
    Widget label(Json data) => Text(
      '关注 ${data['member_num'] == null ? '—' : feedCount(data['member_num'])}  ·  '
      '帖子 ${data['thread_num'] == null ? '—' : feedCount(data['thread_num'])}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (forum['member_num'] != null && forum['thread_num'] != null) {
      return label(forum);
    }
    final name = firstText([forum['name'], forum['forum_name']]);
    if (name.isEmpty) return label(forum);
    return FutureBuilder<Json>(
      future: TiebaApi.forumSummary(name),
      builder: (_, snapshot) => label({...forum, ...?snapshot.data}),
    );
  }
}
