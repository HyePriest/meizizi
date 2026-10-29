import 'package:flutter/material.dart';

import 'bow_share_button.dart';
import 'feed_icons.dart';
import 'thread_feed_action_style.dart';

class ThreadActionBar extends StatelessWidget {
  const ThreadActionBar({
    super.key,
    required this.like,
    required this.onReply,
    required this.onShare,
    this.replyCount = 0,
    this.building = false,
  });
  final Widget like;
  final VoidCallback? onReply;
  final VoidCallback onShare;
  final int replyCount;
  final bool building;
  @override
  Widget build(BuildContext context) => _DetailActions(
    like: like,
    onReply: onReply,
    onShare: onShare,
    building: building,
    replyCount: replyCount,
  );
}

class CommentActionBar extends StatelessWidget {
  const CommentActionBar({
    super.key,
    required this.like,
    required this.onReply,
    required this.onShare,
    this.floor = '',
    this.building = false,
  });
  final Widget like;
  final VoidCallback? onReply;
  final VoidCallback onShare;
  final String floor;
  final bool building;
  @override
  Widget build(BuildContext context) => _DetailActions(
    like: like,
    onReply: onReply,
    onShare: onShare,
    building: building,
    floor: floor,
  );
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.like,
    required this.onReply,
    required this.onShare,
    required this.building,
    this.replyCount,
    this.floor = '',
  });
  final Widget like;
  final VoidCallback? onReply;
  final VoidCallback onShare;
  final bool building;
  final int? replyCount;
  final String floor;
  @override
  Widget build(BuildContext context) {
    final color = ThreadFeedActionStyle.color(context);
    return TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: TextButton(
              onPressed: onReply,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(color: color),
                    child: FeedIcon(
                      building ? FeedGlyph.brick : FeedGlyph.comment,
                      size: 20,
                    ),
                  ),
                  if (replyCount != null) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$replyCount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: BowShareButton(onShare: onShare, size: 22, color: color),
          ),
          Flexible(child: like),
          if (floor.isNotEmpty) const Spacer(),
          if (floor.isNotEmpty)
            Flexible(
              child: Text(
                floor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
            ),
        ],
      ),
    );
  }
}

class PostActionBar extends StatelessWidget {
  const PostActionBar({
    super.key,
    required this.like,
    required this.onReply,
    required this.onFloor,
    required this.floorCount,
    required this.ip,
  });
  final Widget like;
  final VoidCallback? onReply;
  final VoidCallback onFloor;
  final int floorCount;
  final String ip;

  @override
  Widget build(BuildContext context) => TextButtonTheme(
    data: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 12),
      ),
    ),
    child: Row(
      children: [
        Expanded(flex: 5, child: like),
        Expanded(
          flex: 3,
          child: TextButton.icon(
            onPressed: onReply,
            icon: const Icon(Icons.reply, size: 16),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('回复', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        if (floorCount > 0)
          Expanded(
            flex: 4,
            child: TextButton(
              onPressed: onFloor,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '楼中楼 $floorCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        if (ip.isNotEmpty)
          Expanded(
            flex: 4,
            child: Tooltip(
              message: 'IP 属地：$ip',
              child: Text(
                ip,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
      ],
    ),
  );
}
