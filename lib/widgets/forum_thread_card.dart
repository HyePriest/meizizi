import 'package:flutter/material.dart';

import 'feed_list_item.dart';

import '../data/models.dart';
import '../data/share_content.dart';
import '../pages/reading_page.dart';
import 'app_snack_bar.dart';
import 'post_widgets.dart';
import 'thread_feed_actions.dart';
import 'thread_thumbnails.dart';

class ForumThreadCard extends StatelessWidget {
  const ForumThreadCard({
    super.key,
    required this.thread,
    required this.user,
    required this.forum,
    this.latestReply = false,
    this.levelNames = const {},
    this.onLikeChanged,
  });
  final Json thread, user;
  final String forum;
  final bool latestReply;
  final Map<int, String> levelNames;
  final void Function(Json source, Json patch)? onLikeChanged;

  Future<void> _sharePost(BuildContext context) async {
    try {
      await ShareContent.post(
        threadId: '${thread['id']}',
        title: firstText([thread['title']]),
        forum: forum,
        post: {
          ...thread,
          'author': {...user, ...object(thread['author'])},
        },
      ).share();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('无法打开分享，请稍后重试')));
      }
    }
  }

  void _openPost(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReadingPage(
        previewThread: {...thread, 'author': user},
        levelNames: levelNames,
        threadId: '${thread['id']}',
        title: '${thread['title']}',
        forum: forum,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FeedListItem(
    separatorGap: 2,
    child: InkWell(
      onTap: () => _openPost(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserHeader(
              user: user,
              subtitle: threadTimeLabel(thread, latestReply: latestReply),
              showForumLevel: true,
              levelNames: levelNames,
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
                    if (contentParts(thread['abstract']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          contentParts(thread['abstract'])
                              .map((p) => p['text'] ?? '')
                              .join(),
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
              onOpen: () => _openPost(context),
              onShare: () => _sharePost(context),
              onLikeChanged: onLikeChanged,
            ),
          ],
        ),
      ),
    ),
  );
}
