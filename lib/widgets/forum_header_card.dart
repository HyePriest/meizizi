import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/tieba_api.dart' show TiebaApi;
export '../data/models.dart' show forumCoverUrl;
import 'forum_widgets.dart';
import 'home_forum_stats.dart';
import 'post_widgets.dart';
import 'reliable_image.dart';

class ForumHeaderCard extends StatelessWidget {
  const ForumHeaderCard({
    super.key,
    required this.forum,
    required this.name,
    required this.trailing,
    this.level = const {},
    this.levelNames = const {},
    this.onDetails,
    this.showBackground = true,
  });
  final Json forum, level;
  final String name;
  final Widget trailing;
  final Map<int, String> levelNames;
  final VoidCallback? onDetails;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final darkTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: const Color(0xff18212c),
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white70,
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
    );
    final content = Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    button: onDetails != null,
                    label: '查看$name吧的更多内容',
                    child: GestureDetector(
                      onTap: onDetails,
                      child: ForumAvatar(
                        forum: {...forum, 'name': name},
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: onDetails,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name吧',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (number(level['level_id']) > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: ForumLevelBadge(
                                user: level,
                                levelNames: levelNames,
                              ),
                            ),
                          Text(
                            '关注 ${feedCount(forum['member_num']).toLowerCase()} · 帖子 ${feedCount(forum['thread_num']).toLowerCase()}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
              if (onDetails != null)
                InkWell(
                  onTap: onDetails,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            forumDescription(forum),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return showBackground
        ? ForumCover(forum: {...forum, 'name': name}, child: content)
        : content;
  }
}

class ForumCover extends StatelessWidget {
  const ForumCover({
    super.key,
    required this.forum,
    required this.child,
    this.radius = 20,
    this.imageHeight,
  });
  final Json forum;
  final Widget child;
  final double radius;
  final double? imageHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direct = forumCoverUrl(forum);
    final name = forumName(forum);
    return FutureBuilder<Json>(
      future: direct.isEmpty && name.isNotEmpty
          ? TiebaApi.forumSummary(name)
          : null,
      builder: (context, snapshot) {
        final cover = direct.isNotEmpty
            ? direct
            : forumCoverUrl(snapshot.data ?? {});
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: imageHeight == null ? 0 : null,
                height: imageHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        const Color(0xff18212c),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: cover.isEmpty
                      ? null
                      : ReliableImage(
                          urls: [cover],
                          fit: BoxFit.cover,
                          cacheWidth: 1080,
                          fallback: const SizedBox.expand(),
                        ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: .25),
                        Colors.black.withValues(alpha: .65),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}
