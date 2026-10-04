import 'package:flutter/material.dart';

import '../data/models.dart';
import '../pages/reading_page.dart';
import 'post_widgets.dart';
import 'thread_thumbnails.dart';

class ForumThreadCard extends StatelessWidget {
  const ForumThreadCard({
    super.key,
    required this.thread,
    required this.user,
    required this.forum,
    this.latestReply = false,
    this.levelNames = const {},
  });
  final Json thread, user;
  final String forum;
  final bool latestReply;
  final Map<int, String> levelNames;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReadingPage(
            threadId: '${thread['id']}',
            title: '${thread['title']}',
            forum: forum,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserHeader(
              user: user,
              subtitle: threadTimeLabel(thread, latestReply: latestReply),
              showForumLevel: true,
              levelNames: levelNames,
            ),
            const SizedBox(height: 10),
            Text(
              firstText([thread['title']], '查看帖子'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (contentParts(thread['abstract']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  contentParts(thread['abstract'])
                      .map((p) => p['text'] ?? '')
                      .join(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ThreadThumbnails(thread: thread),
            const SizedBox(height: 8),
            Text(
              '${thread['reply_num'] ?? 0} 条回复',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
