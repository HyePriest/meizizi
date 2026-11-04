import 'package:flutter/material.dart';

import '../data/models.dart';
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
    final summary = objects(thread['abstract'])
        .map((p) => p['text'] ?? '')
        .join();
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
                  Transform.translate(
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
                          child: Text(forum.isEmpty ? '无法取得所属吧' : '屏蔽 $forum吧'),
                        ),
                        PopupMenuItem(
                          value: () => onBlock('user'),
                          enabled: userKey(user, thread).isNotEmpty,
                          child: Text('屏蔽 ${author(user)}'),
                        ),
                      ],
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
                      ThreadThumbnails(thread: thread),
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
