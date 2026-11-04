import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import 'bow_share_button.dart';
import 'feed_icons.dart';
import 'like_button.dart';
import 'thread_feed_action_style.dart';

class ThreadFeedActions extends StatelessWidget {
  const ThreadFeedActions({
    super.key,
    required this.thread,
    required this.onOpen,
    required this.onShare,
    this.onLikeChanged,
  });

  final Json thread;
  final VoidCallback onOpen;
  final Future<void> Function() onShare;
  final void Function(Json source, Json patch)? onLikeChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: BowShareButton(
                onShare: onShare,
                color: ThreadFeedActionStyle.color(context),
                visualSize: ThreadFeedActionStyle.iconSize,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  foregroundColor: ThreadFeedActionStyle.color(context),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: ThreadFeedActionStyle.iconSize / 22,
                        child: IconTheme(
                          data: IconThemeData(
                            color: ThreadFeedActionStyle.color(context),
                          ),
                          child: FeedIcon(
                            LocalStore.instance.buildingMode
                                ? FeedGlyph.brick
                                : FeedGlyph.comment,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Transform.scale(
                        scale: ThreadFeedActionStyle.numberScale,
                        child: Text(
                          thread['reply_num'] == null
                              ? '—'
                              : '${number(thread['reply_num'])}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: LikeButton(
                key: ValueKey(
                  'feed-like-${AuthStore.instance.activeId}-${thread['id']}',
                ),
                threadId: '${thread['id']}',
                data: thread,
                onChanged: onLikeChanged,
                feedStyle: true,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
