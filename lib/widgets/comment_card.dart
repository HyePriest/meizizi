import 'package:flutter/material.dart';

import '../data/models.dart';
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
    required this.onReport,
    this.isOriginalPoster = false,
    this.building = false,
    this.nested = false,
    this.highlighted = false,
    this.fullWidthContent = false,
    this.label,
    this.onTap,
    this.preview,
    this.levelNames = const {},
    this.like,
    this.ip = '',
    this.ipWidget,
    this.onBlock,
    this.footer,
  });
  final Json user;
  final Widget? like;
  final Widget? footer;
  final String ip;
  final Widget? ipWidget;
  final VoidCallback? onBlock;
  final Map<int, String> levelNames;
  final String subtitle;
  final Widget content, actions;
  final Widget? preview;
  final String? label;
  final bool isOriginalPoster, nested, fullWidthContent;
  final bool highlighted;
  final bool building;
  final VoidCallback? onTap;
  final VoidCallback onShare, onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final metadata = theme.labelSmall?.copyWith(color: colors.onSurfaceVariant);
    return Material(
      color: highlighted
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: .12),
              colors.surface,
            )
          : colors.surface,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(label!, style: metadata),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => openUser(context, user),
                        child: UserAvatar(user: user, size: nested ? 34 : 38),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, authorConstraints) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => openUser(context, user),
                                child: Text(
                                  author(user),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: authorConstraints.maxWidth,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: ForumLevelBadge(
                                        user: user,
                                        levelNames: levelNames,
                                      ),
                                    ),
                                  ),
                                  if (isOriginalPoster)
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: FittedBox(
                                        child: OriginalPosterBadge(
                                          building: building,
                                        ),
                                      ),
                                    ),
                                  if (forumRole(user).isNotEmpty)
                                    ForumRoleBadge(user: user),
                                  Text(subtitle, style: metadata),
                                  if (ipWidget != null)
                                    ipWidget!
                                  else if (ip.isNotEmpty)
                                    Text(ip, style: metadata),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: PopupMenuButton<String>(
                          tooltip: '评论选项',
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: colors.onSurfaceVariant,
                          ),
                          onSelected: (value) {
                            if (value == 'share') onShare();
                            if (value == 'block') onBlock?.call();
                            if (value == 'report') onReport();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'report',
                              child: Text(fullWidthContent ? '举报帖子' : '举报评论'),
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
                  const SizedBox(height: 8),
                  content,
                  const SizedBox(height: 4),
                  footer ??
                      (fullWidthContent && like != null
                          ? Row(children: [like!, const Spacer(), actions])
                          : actions),
                  if (preview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SizedBox(width: double.infinity, child: preview),
                    ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: .5,
            color: colors.outlineVariant.withValues(alpha: .65),
          ),
        ],
      ),
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
    this.onReplyTap,
  });
  final List<Json> replies;
  final int total;
  final Map<String, Json> users;
  final VoidCallback onTap;
  final ValueChanged<Json>? onReplyTap;

  List<Json> _previewParts(Json reply) {
    final parts = contentParts(reply['content'])
        .map((part) => {...part})
        .toList();
    if (parts.isNotEmpty && number(parts.first['type']) == 0) {
      parts.first['text'] = '${parts.first['text'] ?? ''}'.replaceFirst(
        RegExp(r'^\s*[:：]\s*'),
        '',
      );
    }
    return parts;
  }

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
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final reply in visible)
                  InkWell(
                    onTap: () =>
                        onReplyTap == null ? onTap() : onReplyTap!(reply),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InlinePostContent(
                        prefix:
                            '${author({...?users['${reply['author_id']}'], ...object(reply['author'])})}：',
                        prefixColor: colors.primary,
                        parts: _previewParts(reply),
                        highlightReplyTarget: false,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
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
      ),
    );
  }
}
