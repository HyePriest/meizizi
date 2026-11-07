import 'package:flutter/material.dart';

import '../data/models.dart';
import 'desktop_layout.dart';
import 'feed_list_item.dart';
import 'forum_widgets.dart';
import 'home_forum_stats.dart';
import 'thread_feed_actions.dart';
import 'thread_thumbnails.dart';

class HomeThreadCard extends StatelessWidget {
  const HomeThreadCard({
    super.key,
    required this.thread,
    required this.user,
    required this.onOpenForum,
    required this.onOpen,
    required this.onShare,
    required this.onBlock,
    this.onLikeChanged,
  });

  final Json thread, user;
  final VoidCallback onOpenForum, onOpen;
  final Future<void> Function() onShare;
  final ValueChanged<String> onBlock;
  final void Function(Json source, Json patch)? onLikeChanged;

  @override
  Widget build(BuildContext context) {
    final forum = threadForumName(thread);
    final forumInfo = {
      ...object(thread['forum']),
      ...object(thread['forum_info']),
      'name': forum,
      'avatar': firstText([
        object(thread['forum_info'])['avatar'],
        object(thread['forum'])['avatar'],
        thread['forum_avatar'],
      ]),
    };
    final comment = feedComment(thread);
    // A recommended comment shows what was said, under the thread it is in;
    // its own title is only "回复：<thread title>".
    final summary =
        objects(
              comment == null
                  ? thread['abstract']
                  : thread['first_post_content'] ?? thread['abstract'],
            )
            // Text, links and @mentions; images show as thumbnails below.
            .where(
              (p) =>
                  comment == null ||
                  const {0, 1, 4}.contains(number(p['type'])),
            )
            .map((p) => p['text'] ?? '')
            .join()
            .trim();
    return FeedListItem(
      separatorGap: 2,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: forum.isEmpty ? null : onOpenForum,
                      child: Row(
                        children: [
                          ForumAvatar(forum: forumInfo, size: 42),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  forum.isEmpty ? '所属吧信息暂不可用' : '$forum吧',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                                HomeForumStats(forum: forumInfo),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Desktop: shown only while the mouse is over the card.
                  ShowOnHover(
                    child: Transform.translate(
                      offset: const Offset(0, -6),
                      child: PopupMenuButton<VoidCallback>(
                        tooltip: '屏蔽内容',
                        icon: const Icon(Icons.close, size: 20),
                        // Keep the target that was displayed when the menu opened,
                        // even if the card rebuilds while the popup is visible.
                        onSelected: (block) => block(),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: () => onBlock('forum'),
                            enabled: forum.isNotEmpty,
                            child: Text(
                              forum.isEmpty ? '无法取得所属吧' : '屏蔽 $forum吧',
                            ),
                          ),
                          PopupMenuItem(
                            value: () => onBlock('user'),
                            enabled: userKey(user, thread).isNotEmpty,
                            child: Text('屏蔽 ${author(user)}'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (comment == null) ...[
                        Text(
                          firstText([thread['title']], '查看帖子'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (summary.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ] else if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ThreadThumbnails(thread: thread),
                      if (comment != null)
                        _OriginalThread(title: comment.threadTitle),
                    ],
                  ),
                ),
              ),
              ThreadFeedActions(
                thread: thread,
                onOpen: onOpen,
                onShare: onShare,
                onLikeChanged: onLikeChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The thread a recommended comment was posted in.
class _OriginalThread extends StatelessWidget {
  const _OriginalThread({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '原帖  ',
              style: TextStyle(color: colors.primary),
            ),
            TextSpan(text: title.isEmpty ? '查看帖子' : title),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}
