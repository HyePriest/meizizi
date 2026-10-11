import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/share_content.dart';
import '../pages/user_page.dart';
import 'post_widgets.dart';

class CommentCard extends StatelessWidget {
  const CommentCard({
    super.key,
    required this.user,
    required this.subtitle,
    required this.content,
    required this.actions,
    required this.onShare,
    required this.onCopyLink,
    this.isOriginalPoster = false,
    this.nested = false,
    this.fullWidthContent = false,
    this.label,
    this.onTap,
    this.preview,
    this.levelNames = const {},
    this.like,
    this.ip = '',
    this.onBlock,
  });
  final Json user;
  final Widget? like;
  final String ip;
  final VoidCallback? onBlock;
  final Map<int, String> levelNames;
  final String subtitle;
  final Widget content, actions;
  final Widget? preview;
  final String? label;
  final bool isOriginalPoster, nested, fullWidthContent;
  final VoidCallback? onTap;
  final VoidCallback onShare, onCopyLink;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final indent = nested ? 38.0 : 42.0;
    final body = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, nested ? 14 : 16, 14, nested ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  label!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openUser(context, user),
                  child: UserAvatar(user: user, size: nested ? 28 : 32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) => Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: () => openUser(context, user),
                                      child: Text(
                                        author(user),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  ForumLevelBadge(
                                    user: user,
                                    levelNames: levelNames,
                                  ),
                                  if (isOriginalPoster)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 5),
                                      child: Text(
                                        '楼主',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (like != null)
                              SizedBox(
                                width: (constraints.maxWidth * .26).clamp(
                                  42,
                                  72,
                                ),
                                height: 32,
                                child: TextButtonTheme(
                                  data: TextButtonThemeData(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                      ),
                                      alignment: Alignment.centerRight,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  child: like!,
                                ),
                              ),
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: PopupMenuButton<String>(
                                tooltip: '评论选项',
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.more_vert,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                                onSelected: (value) {
                                  if (value == 'share') {
                                    onShare();
                                  } else if (value == 'block') {
                                    onBlock?.call();
                                  } else {
                                    onCopyLink();
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'share',
                                    child: Text('分享评论'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'copy',
                                    child: Text('复制链接'),
                                  ),
                                  if (onBlock != null)
                                    const PopupMenuItem(
                                      value: 'block',
                                      child: Text('拉黑此人'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (ip.isNotEmpty)
                            Text(
                              'IP：$ip',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(
                left: fullWidthContent ? 0 : indent,
                top: nested ? 8 : 12,
              ),
              child: content,
            ),
            Padding(
              padding: EdgeInsets.only(
                left: fullWidthContent ? 0 : indent,
                top: 4,
              ),
              child: actions,
            ),
            if (preview != null)
              Padding(
                padding: EdgeInsets.only(left: indent, top: 8),
                child: preview,
              ),
          ],
        ),
      ),
    );
    if (nested) {
      return Material(
        color: colors.surface,
        child: Column(
          children: [
            body,
            Padding(
              padding: const EdgeInsets.only(left: 52, right: 14),
              child: Divider(
                height: 1,
                thickness: .5,
                color: colors.outlineVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: body,
    );
  }
}

List<Json> previewReplies(Json post) {
  final raw = post['sub_post_list'];
  final replies = raw is List
      ? objects(raw)
      : objects(object(raw)['sub_post_list']);
  // The request asks the server for its highest-agree replies. Preserve that order
  // when JSON omits their agree counters; don't re-rank missing counts as zero.
  if (replies.every(
    (r) =>
        object(r['agree']).containsKey('agree_num') ||
        r.containsKey('agree_num'),
  )) {
    final original = {
      for (var i = 0; i < replies.length; i++) '${replies[i]['id']}': i,
    };
    replies.sort((a, b) {
      final order = number(object(b['agree'])['agree_num'] ?? b['agree_num'])
          .compareTo(number(object(a['agree'])['agree_num'] ?? a['agree_num']));
      return order != 0
          ? order
          : original['${a['id']}']!.compareTo(original['${b['id']}']!);
    });
  }
  return replies.take(4).toList();
}

class ReplyPreview extends StatelessWidget {
  const ReplyPreview({
    super.key,
    required this.replies,
    required this.total,
    required this.users,
    required this.onTap,
  });
  final List<Json> replies;
  final int total;
  final Map<String, Json> users;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = replies.take(4).toList();
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reply in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${author({...?users['${reply['author_id']}'], ...object(reply['author'])})}：',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(text: contentSummary(reply['content'])),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (total > visible.length || visible.isEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    top: visible.isEmpty ? 0 : 6,
                    bottom: 2,
                  ),
                  child: Text(
                    '查看全部 $total 条回复 ›',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
