import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/emoji.dart';
import '../pages/image_page.dart';
import '../pages/video_page.dart';
import '../pages/user_page.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 36});
  final Json user;
  final double size;
  @override
  Widget build(BuildContext context) {
    final url = avatarUrl(user);
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.person_outline, size: size * .6),
      ),
    );
    return ClipOval(
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class UserHeader extends StatelessWidget {
  const UserHeader({
    super.key,
    required this.user,
    required this.subtitle,
    this.showForumLevel = false,
    this.isOriginalPoster = false,
    this.levelNames = const {},
  });
  final Json user;
  final String subtitle;
  final bool showForumLevel, isOriginalPoster;
  final Map<int, String> levelNames;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      GestureDetector(
        onTap: () => openUser(context, user),
        child: UserAvatar(user: user),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: GestureDetector(
                    onTap: () => openUser(context, user),
                    child: Text(
                      author(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                if (isOriginalPoster)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '楼主',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (showForumLevel) ...[
                  const SizedBox(width: 6),
                  ForumLevelBadge(user: user, levelNames: levelNames),
                ],
              ],
            ),
            Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    ],
  );
}

class ForumLevelBadge extends StatelessWidget {
  const ForumLevelBadge({
    super.key,
    required this.user,
    this.levelNames = const {},
  });
  final Json user;
  final Map<int, String> levelNames;

  @override
  Widget build(BuildContext context) {
    final level = number(user['level_id'] ?? user['user_level']);
    // The PB level is specific to this forum. Explicit non-followers have no badge.
    if (level <= 0 ||
        (user.containsKey('is_like') && !flag(user['is_like'])) ||
        (user.containsKey('is_liked') && !flag(user['is_liked']))) {
      return const SizedBox.shrink();
    }
    final title = firstText([user['level_name'], levelNames[level]]);
    final color = level <= 3
        ? const Color(0xff278543)
        : level <= 9
        ? const Color(0xff2379c5)
        : const Color(0xffb65e00);
    final icon = level <= 3
        ? 1
        : level <= 6
        ? 2
        : level == 7
        ? 3
        : level <= 9
        ? 4
        : level <= 11
        ? 5
        : level <= 13
        ? 6
        : level <= 15
        ? 7
        : 8;
    return Semantics(
      label: '$title $level 级',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Text(title, style: Theme.of(context).textTheme.labelSmall),
            ),
          SizedBox(
            width: 25,
            height: 25,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (level >= 10)
                  Image.asset('assets/levels/$icon.gif', fit: BoxFit.contain)
                else
                  ColorFiltered(
                    // Recolor the original gold art while preserving its alpha and shading.
                    colorFilter: ColorFilter.matrix(
                      level <= 3
                          ? const [
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ]
                          : const [
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              1,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ],
                    ),
                    child: Image.asset(
                      'assets/levels/$icon.gif',
                      fit: BoxFit.contain,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: icon == 8 ? 5 : 0),
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String emojiUrl(Json part) {
  return emojiUrls(part).firstOrNull ?? '';
}

class TiebaEmoji extends StatelessWidget {
  const TiebaEmoji({super.key, required this.part, this.size = 24});
  final Json part;
  final double size;
  @override
  Widget build(BuildContext context) {
    final urls = emojiUrls(part);
    final label = firstText([part['c'], part['text']], '表情');
    Widget load(int index) => index >= urls.length
        ? Text(
            label.startsWith('[') ? label : '[$label]',
            style: const TextStyle(fontSize: 12),
          )
        : Image.network(
            urls[index],
            width: size,
            height: size,
            fit: BoxFit.contain,
            headers: const {'Referer': 'https://tieba.baidu.com/'},
            errorBuilder: (_, _, _) => load(index + 1),
          );
    return Semantics(label: label, child: load(0));
  }
}

class InlinePostContent extends StatelessWidget {
  const InlinePostContent({
    super.key,
    required this.parts,
    this.prefix = '',
    this.prefixColor,
    this.maxLines = 3,
    this.style,
  });
  final List<Json> parts;
  final String prefix;
  final Color? prefixColor;
  final int maxLines;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        if (prefix.isNotEmpty)
          TextSpan(
            text: prefix,
            style: TextStyle(color: prefixColor, fontWeight: FontWeight.w500),
          ),
        for (final part in parts)
          if (number(part['type']) == 2)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: TiebaEmoji(part: part, size: 20),
            )
          else if ([3, 20].contains(number(part['type'])))
            const TextSpan(text: '[图片]')
          else if (number(part['type']) == 5)
            const TextSpan(text: '[视频]')
          else if (number(part['type']) != 52)
            TextSpan(text: firstText([part['text']])),
      ],
    ),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: style ?? const TextStyle(fontSize: 14, height: 1.5),
  );
}

String postImageUrl(Json part, {bool original = false}) {
  final fields = original
      ? [
          'origin_src',
          'origin_pic',
          'big_cdn_src',
          'big_pic',
          'cdn_src',
          'src',
          'src_pic',
          'image_src',
          'original',
          'small_pic',
          'text',
        ]
      : [
          'cdn_src',
          'big_cdn_src',
          'origin_src',
          'src',
          'origin_pic',
          'src_pic',
          'image_src',
          'original',
          'big_pic',
          'small_pic',
          'text',
        ];
  return fields
      .map((field) => httpsImage(part[field]))
      .firstWhere((url) => url.isNotEmpty, orElse: () => '');
}

class PostContent extends StatelessWidget {
  const PostContent({
    super.key,
    required this.parts,
    this.onTextTap,
    this.videoInfo = const {},
    this.textStyle,
  });
  final List<Json> parts;
  final VoidCallback? onTextTap;
  final Json videoInfo;
  final TextStyle? textStyle;
  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final spans = <InlineSpan>[];
    void flush() {
      if (spans.isEmpty) return;
      widgets.add(
        SelectionArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTextTap,
            child: SizedBox(
              width: double.infinity,
              child: Text.rich(
                TextSpan(children: List.of(spans)),
                style: textStyle ?? const TextStyle(fontSize: 16, height: 1.6),
              ),
            ),
          ),
        ),
      );
      spans.clear();
    }

    for (final part in parts) {
      final type = number(part['type']);
      // Type 52 supplies the official client's comment bubble theme, not content.
      if (type == 52) continue;
      if (type == 5 || part['type'] == 'video') {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: VideoPreview(info: {...videoInfo, ...part}),
          ),
        );
      } else if (type == 3 ||
          type == 20 ||
          (type != 2 &&
              firstText([
                part['origin_src'],
                part['origin_pic'],
                part['image_src'],
                part['original'],
                part['big_pic'],
                part['small_pic'],
              ]).isNotEmpty)) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ImagePage(url: postImageUrl(part, original: true)),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _image(part),
              ),
            ),
          ),
        );
      } else if (type == 2) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TiebaEmoji(part: part),
          ),
        );
      } else if ('${part['text'] ?? ''}'.isNotEmpty) {
        spans.add(TextSpan(text: '${part['text']}'));
      } else if (type != 0) {
        spans.add(
          TextSpan(
            text:
                '[${type == 5
                    ? '视频'
                    : type == 10
                    ? '语音'
                    : '暂不支持的内容'}]',
          ),
        );
      }
    }
    flush();
    if (!parts.any((p) => number(p['type']) == 5 || p['type'] == 'video') &&
        videoSource(videoInfo).isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: VideoPreview(info: videoInfo),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _image(Json part) {
    final url = postImageUrl(part);
    if (url.isEmpty) return const Text('[图片地址不可用]');
    return Image.network(
      url,
      fit: BoxFit.contain,
      headers: const {'Referer': 'https://tieba.baidu.com/'},
      errorBuilder: (_, _, _) =>
          const Padding(padding: EdgeInsets.all(24), child: Text('图片加载失败')),
    );
  }
}

class VideoPreview extends StatelessWidget {
  const VideoPreview({super.key, required this.info, this.onTap});
  final Json info;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = videoSource(info), cover = videoThumbnail(info);
    final duration = number(info['video_duration']);
    return Semantics(
      label: '视频预览',
      button: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: InkWell(
            onTap:
                onTap ??
                (url.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VideoPage(url: url),
                        ),
                      )),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Text('视频封面暂不可用')),
                ),
                if (cover.isNotEmpty)
                  Image.network(
                    cover,
                    fit: BoxFit.cover,
                    headers: const {'Referer': 'https://tieba.baidu.com/'},
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                if (duration > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
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
