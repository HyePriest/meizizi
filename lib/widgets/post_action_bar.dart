import 'package:flutter/material.dart';

class ThreadActionBar extends StatelessWidget {
  const ThreadActionBar({
    super.key,
    required this.like,
    required this.onReply,
    required this.onShare,
  });
  final Widget like;
  final VoidCallback? onReply;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextButton.styleFrom(
      backgroundColor: colors.surfaceContainerLow,
      foregroundColor: colors.onSurfaceVariant,
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextButtonTheme(
        data: TextButtonThemeData(style: style),
        child: Row(
          children: [
            Expanded(child: like),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: '回复',
                child: TextButton(
                  onPressed: onReply,
                  child: const Icon(Icons.chat_bubble_outline, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: '分享',
                child: TextButton(
                  onPressed: onShare,
                  child: const Icon(Icons.share_outlined, size: 20),
                ),
              ),
            ),
          ],
        ),
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
                'IP：$ip',
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
