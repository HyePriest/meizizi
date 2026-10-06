import 'package:flutter/material.dart';

import '../data/models.dart';
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
                Image.asset('assets/levels/$icon.gif', fit: BoxFit.contain),
                Padding(
                  padding: EdgeInsets.only(top: icon == 8 ? 5 : 0),
                  child: Text(
                    '$level',
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffb65e00),
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
  for (final value in [part['src'], part['text'], part['c']]) {
    final direct = httpsImage(value);
    if (RegExp(r'image_emoticon(?:1)?\.png(?:\?|$)').hasMatch(direct)) {
      return 'https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon1.png';
    }
    if (direct.isNotEmpty) return direct;
    final match = RegExp(r'image_emoticon(\d*)').firstMatch('${value ?? ''}');
    if (match != null) {
      final id = match.group(1)!;
      return 'https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon${id.isEmpty ? '1' : id}.png';
    }
  }
  return '';
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
  const PostContent({super.key, required this.parts, this.onTextTap});
  final List<Json> parts;
  final VoidCallback? onTextTap;
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
                style: const TextStyle(fontSize: 16, height: 1.65),
              ),
            ),
          ),
        ),
      );
      spans.clear();
    }

    for (final part in parts) {
      final type = number(part['type']);
      if (type == 5) {
        flush();
        final url = httpsImage(
          firstText([part['video_url'], part['link'], part['text']]),
        );
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: url.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => VideoPage(url: url),
                      ),
                    ),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(url.isEmpty ? '视频地址不可用' : '播放视频'),
            ),
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
        final url = emojiUrl(part);
        final label = firstText([part['c'], part['text']], '表情');
        if (url.isEmpty) {
          spans.add(TextSpan(text: '[$label]'));
        } else {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Semantics(
                label: label,
                child: Image.network(
                  url,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      Text('[$label]', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          );
        }
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
