import 'package:flutter/material.dart';

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
        Expanded(flex: 3, child: like),
        Expanded(
          flex: 3,
          child: TextButton.icon(
            onPressed: onReply,
            icon: const Icon(Icons.reply, size: 16),
            label: const Text(
              '回复',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (floorCount > 0)
          Expanded(
            flex: 4,
            child: TextButton(
              onPressed: onFloor,
              child: Text(
                '楼中楼 $floorCount',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
