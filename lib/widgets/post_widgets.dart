import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_snack_bar.dart';
import 'feed_icons.dart';

import '../data/models.dart';
import '../data/tieba_api.dart' show TiebaApi;
import '../data/emoji.dart';
import 'tieba_emoji.dart';

export 'tieba_emoji.dart' show TiebaEmoji;
import '../pages/image_page.dart';
import '../pages/video_page.dart';
import '../pages/user_page.dart';
import 'voice_player.dart';
import 'reliable_image.dart';
import 'hold_image_preview.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40});
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
          : ReliableImage(
              urls: [url],
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              fallback: fallback,
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
            if (showForumLevel && forumRole(user).isNotEmpty)
              ForumRoleBadge(user: user),
          ],
        ),
      ),
    ],
  );
}

class _IdentityBadge extends StatelessWidget {
  const _IdentityBadge({
    required this.label,
    required this.color,
    this.fontSize = 9,
  });
  final String label;
  final Color color;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, .3)!
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ink.withValues(alpha: .32), width: .6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    );
  }
}

class OriginalPosterBadge extends StatelessWidget {
  const OriginalPosterBadge({super.key, this.building = false});
  final bool building;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '楼主',
    child: Tooltip(
      message: '楼主',
      child: SizedBox(
        width: building ? 28 : 24,
        height: 28,
        child: Center(
          child: IconTheme(
            data: IconThemeData(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xffffb56b)
                  : const Color(0xffb85b12),
            ),
            child: building
                ? Image.asset(
                    'assets/badges/work-glove.png',
                    width: 27,
                    height: 27,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  )
                : const FeedIcon(FeedGlyph.pencil, size: 22),
          ),
        ),
      ),
    ),
  );
}

class ForumRoleBadge extends StatelessWidget {
  const ForumRoleBadge({super.key, required this.user});
  final Json user;
  @override
  Widget build(BuildContext context) {
    final role = forumRole(user);
    return _IdentityBadge(label: role, color: const Color(0xff8656ad));
  }
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
    final level =
        [
          number(user['level_id']),
          number(user['user_level']),
        ].where((n) => n > 0).firstOrNull ??
        0;
    // The PB level is specific to this forum. Explicit non-followers have no badge.
    if (level <= 0 ||
        (user.containsKey('is_like') && !flag(user['is_like'])) ||
        (user.containsKey('is_liked') && !flag(user['is_liked']))) {
      return const SizedBox.shrink();
    }
    final title = firstText([user['level_name'], levelNames[level]]);
    final color = level <= 3
        ? const Color(0xff3d8853)
        : level <= 9
        ? const Color(0xff2378bd)
        : const Color(0xffa65b00);
    final diamond = Image.asset(
      'assets/levels/diamond.png',
      fit: BoxFit.contain,
    );
    final background = Color.alphaBlend(
      color.withValues(alpha: .16),
      Theme.of(context).colorScheme.surface,
    );
    return Semantics(
      label: '$title $level 级',
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 10,
            right: 0,
            top: 2,
            bottom: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 19,
                height: 19,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: level >= 10
                          ? ColorFiltered(
                              colorFilter: const ColorFilter.matrix([
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
                                .82,
                                0,
                                0,
                                0,
                                0,
                                0,
                                1,
                                0,
                              ]),
                              child: diamond,
                            )
                          : ColorFiltered(
                              colorFilter: ColorFilter.matrix(
                                level <= 3
                                    ? const [
                                        0,
                                        0,
                                        1,
                                        0,
                                        25,
                                        0,
                                        .86,
                                        0,
                                        0,
                                        22,
                                        0,
                                        0,
                                        1,
                                        0,
                                        25,
                                        0,
                                        0,
                                        0,
                                        1,
                                        0,
                                      ]
                                    : const [
                                        0,
                                        0,
                                        .6,
                                        0,
                                        15,
                                        0,
                                        .77,
                                        0,
                                        0,
                                        10,
                                        .98,
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
                              child: diamond,
                            ),
                    ),
                    // The diamond's broad face sits above the square image's center.
                    Positioned(
                      left: 2,
                      right: 2,
                      top: 2,
                      height: 12,
                      child: Center(
                        child: Text(
                          '$level',
                          textAlign: TextAlign.center,
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                          style: const TextStyle(
                            fontSize: 8,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9.5,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Color.lerp(color, Colors.white, .38)
                          : color,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String emojiUrl(Json part) {
  return emojiUrls(part).firstOrNull ?? '';
}

List<InlineSpan> _commentTextSpans(
  BuildContext context,
  Json part, {
  required bool highlightReplyTarget,
  bool linkReplyTarget = false,
  TextStyle? baseStyle,
}) {
  final text = firstText([part['text']]);
  if (!highlightReplyTarget) return [TextSpan(text: text)];
  final targetStyle = TextStyle(
    color: Theme.of(context).colorScheme.primary,
    fontWeight: FontWeight.normal,
  );
  InlineSpan target(String name) => linkReplyTarget
      ? WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _ReplyUserLink(
            user: part,
            name: name,
            style: (baseStyle ?? const TextStyle(fontSize: 15, height: 1.55))
                .merge(targetStyle),
          ),
        )
      : TextSpan(text: name.isEmpty ? '该用户' : name, style: targetStyle);
  if (number(part['type']) == 4) {
    return [target(text)];
  }
  // Some endpoints send the reply prefix as plain text instead of a type-4 user.
  final match = RegExp(r'^(\s*回复\s*)([^:：\n]+?)(\s*[:：])').firstMatch(text);
  if (match == null) return [TextSpan(text: text)];
  return [
    TextSpan(text: match[1]),
    target(match[2]!),
    TextSpan(text: match[3]),
    TextSpan(text: text.substring(match.end)),
  ];
}

class _ReplyUserLink extends StatefulWidget {
  const _ReplyUserLink({
    required this.user,
    required this.name,
    required this.style,
  });
  final Json user;
  final String name;
  final TextStyle style;
  @override
  State<_ReplyUserLink> createState() => _ReplyUserLinkState();
}

class _ReplyUserLinkState extends State<_ReplyUserLink> {
  bool _opening = false;
  Json _resolvedUser = {};
  TiebaApi? _nameApi;

  @override
  void initState() {
    super.initState();
    _resolveMissingName();
  }

  @override
  void didUpdateWidget(covariant _ReplyUserLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user['uid'] != widget.user['uid'] ||
        oldWidget.user['portrait'] != widget.user['portrait'] ||
        oldWidget.name != widget.name) {
      _resolvedUser = {};
      _resolveMissingName();
    }
  }

  Future<void> _resolveMissingName() async {
    _nameApi?.close();
    _nameApi = null;
    if (widget.name.isNotEmpty) return;
    final user = {
      ...widget.user,
      'id': firstText([
        widget.user['uid'],
        widget.user['user_id'],
        widget.user['id'],
      ]),
    };
    if (number(user['id']) <= 0 && firstText([user['portrait']]).isEmpty)
      return;
    final api = _nameApi = TiebaApi();
    try {
      final result = await api.userProfile(user);
      if (mounted && identical(_nameApi, api)) {
        setState(() => _resolvedUser = object(result.data['user']));
      }
    } catch (_) {
      // A deleted or unavailable account still renders as a user reference.
    } finally {
      api.close();
      if (identical(_nameApi, api)) _nameApi = null;
    }
  }

  @override
  void dispose() {
    _nameApi?.close();
    super.dispose();
  }

  String get _name => widget.name.isNotEmpty
      ? widget.name
      : firstText([
          _resolvedUser['name_show'],
          _resolvedUser['show_nickname'],
          _resolvedUser['name'],
        ], '该用户');

  Future<void> _open() async {
    if (_opening) return;
    final user = {
      ...widget.user,
      ..._resolvedUser,
      'id': firstText([
        widget.user['uid'],
        widget.user['user_id'],
        widget.user['id'],
      ]),
      'name_show': _name,
    };
    if (number(user['id']) > 0 || firstText([user['portrait']]).isNotEmpty) {
      openUser(context, user);
      return;
    }
    _opening = true;
    final api = TiebaApi();
    try {
      if (widget.name.isEmpty && _resolvedUser.isEmpty) return;
      final name = _name.trim().replaceFirst(RegExp(r'^@'), '');
      final result = await api.searchUsers(name, 1);
      final matches = result.items
          .where(
            (u) => [
              u['name'],
              u['name_show'],
              u['user_nickname'],
              u['show_nickname'],
            ].any((value) => value == name),
          )
          .toList();
      if (!mounted) return;
      if (matches.length == 1) {
        openUser(context, matches.single);
      } else {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('暂时无法准确定位该用户')));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showAppSnackBar(const AppSnackBar(content: Text('用户主页加载失败，请稍后重试')));
    } finally {
      api.close();
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Text(_name, style: widget.style, textScaler: TextScaler.noScaling),
    ),
  );
}

class InlinePostContent extends StatelessWidget {
  const InlinePostContent({
    super.key,
    required this.parts,
    this.prefix = '',
    this.prefixColor,
    this.maxLines = 3,
    this.style,
    this.highlightReplyTarget = false,
  });
  final List<Json> parts;
  final String prefix;
  final Color? prefixColor;
  final int maxLines;
  final TextStyle? style;
  final bool highlightReplyTarget;
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
          else if (number(part['type']) == 10)
            const TextSpan(text: '[语音]')
          else if (number(part['type']) != 52)
            ..._commentTextSpans(
              context,
              part,
              highlightReplyTarget: highlightReplyTarget,
            ),
      ],
    ),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: style ?? const TextStyle(fontSize: 14, height: 1.5),
  );
}

String postImageUrl(Json part, {bool original = false}) =>
    postImageUrls(part, original: original).firstOrNull ?? '';

List<String> postImageUrls(Json part, {bool original = false}) {
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
  return imageSources(fields.map((field) => part[field]));
}

class PostContent extends StatelessWidget {
  const PostContent({
    super.key,
    required this.parts,
    this.onTextTap,
    this.openImages = true,
    this.adaptiveImages = false,
    this.videoInfo = const {},
    this.textStyle,
    this.highlightReplyTarget = false,
  });
  final List<Json> parts;
  final VoidCallback? onTextTap;
  final bool openImages;
  final bool adaptiveImages;
  final Json videoInfo;
  final TextStyle? textStyle;
  final bool highlightReplyTarget;
  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final spans = <InlineSpan>[];
    final images = parts
        .where(
          (p) =>
              [3, 20].contains(number(p['type'])) ||
              (number(p['type']) != 2 &&
                  number(p['type']) != 10 &&
                  firstText([
                    p['origin_src'],
                    p['origin_pic'],
                    p['image_src'],
                    p['original'],
                    p['big_pic'],
                    p['small_pic'],
                  ]).isNotEmpty),
        )
        .map((p) => postImageUrl(p, original: true))
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    void flush() {
      if (spans.isEmpty) return;
      if (spans.every((s) => s is TextSpan && s.toPlainText().trim().isEmpty)) {
        spans.clear();
        return;
      }
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

    final pendingImages = <Json>[];
    void flushImages() {
      if (pendingImages.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _PostImageGroup(
            parts: List.of(pendingImages),
            images: images,
            openImages: openImages,
          ),
        ),
      );
      pendingImages.clear();
    }

    for (final part in parts) {
      final type = number(part['type']);
      if (adaptiveImages) {
        if (_isPostImage(part)) {
          flush();
          pendingImages.add(part);
          continue;
        }
        // Whitespace between adjacent images does not create separate groups.
        if (pendingImages.isNotEmpty &&
            type == 0 &&
            firstText([part['text']]).trim().isEmpty)
          continue;
        if (type != 52) flushImages();
      }
      // Type 52 supplies the official client's comment bubble theme, not content.
      if (type == 52) continue;
      if (type == 10) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: VoicePlayer(part: part),
          ),
        );
      } else if (type == 5 || part['type'] == 'video') {
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
              onTap: openImages
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImagePage(
                          url: postImageUrl(part, original: true),
                          urls: images,
                        ),
                      ),
                    )
                  : null,
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
      } else if (type == 4 || '${part['text'] ?? ''}'.isNotEmpty) {
        spans.addAll(
          _commentTextSpans(
            context,
            part,
            highlightReplyTarget: highlightReplyTarget,
            linkReplyTarget: true,
            baseStyle: textStyle,
          ),
        );
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
    flushImages();
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
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _image(Json part) {
    final url = postImageUrl(part);
    if (url.isEmpty) return const Text('[图片地址不可用]');
    final image = ReliableImage(
      urls: postImageUrls(part),
      cacheWidth: 1080,
      fit: BoxFit.contain,
    );
    final size = firstText([part['bsize']]).split(',');
    final width = number(part['width']) > 0
        ? number(part['width'])
        : number(size.first);
    final height = number(part['height']) > 0
        ? number(part['height'])
        : (size.length > 1 ? number(size[1]) : 0);
    if (width > 0 && height > 0)
      return AspectRatio(aspectRatio: width / height, child: image);
    return image;
  }
}

bool _isPostImage(Json part) =>
    [3, 20].contains(number(part['type'])) ||
    (![2, 5, 10, 52].contains(number(part['type'])) &&
        firstText([
          part['origin_src'],
          part['origin_pic'],
          part['image_src'],
          part['original'],
          part['big_pic'],
          part['small_pic'],
        ]).isNotEmpty);

double _postImageRatio(Json part) {
  final size = firstText([part['bsize']]).split(',');
  final width = number(part['width']) > 0
      ? number(part['width'])
      : number(size.first);
  final height = number(part['height']) > 0
      ? number(part['height'])
      : (size.length > 1 ? number(size[1]) : 0);
  return width > 0 && height > 0 ? width / height : 1;
}

/// Keeps source order and reserves thumbnail geometry before network completion.
class _PostImageGroup extends StatelessWidget {
  const _PostImageGroup({
    required this.parts,
    required this.images,
    required this.openImages,
  });
  final List<Json> parts;
  final List<String> images;
  final bool openImages;

  Widget tile(
    BuildContext context,
    Json part,
    double width,
    double height, {
    bool crop = true,
  }) {
    final ratio = _postImageRatio(part);
    return SizedBox(
      width: width,
      height: height,
      child: HoldImagePreview(
        urls: postImageUrls(part, original: true),
        child: GestureDetector(
          onTap: openImages
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImagePage(
                      url: postImageUrl(part, original: true),
                      urls: images,
                    ),
                  ),
                )
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                ReliableImage(
                  urls: postImageUrls(part),
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1440),
                  fit: crop ? BoxFit.cover : BoxFit.contain,
                ),
                if (ratio < .4)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          '长图',
                          style: TextStyle(color: Colors.white, fontSize: 11),
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth;
      if (parts.length == 1) {
        final ratio = _postImageRatio(parts.single);
        final cap = ratio < .85
            ? 260.0
            : ratio < 1.2
            ? 300.0
            : 680.0;
        var width = math.min(available, cap);
        final maxHeight = math.min(
          420.0,
          MediaQuery.sizeOf(context).height * .52,
        );
        var height = width / ratio;
        final longImage = ratio < .4;
        if (height > maxHeight) {
          height = maxHeight;
          if (!longImage) width = height * ratio;
        }
        return tile(context, parts.single, width, height, crop: longImage);
      }
      const gap = 6.0;
      final rows = <Widget>[];
      var offset = 0;
      while (offset < parts.length) {
        final remaining = parts.length - offset;
        final columns = parts.length == 4 || remaining == 4
            ? 2
            : remaining >= 3 && available >= 300
            ? 3
            : math.min(remaining, 2);
        final row = parts.sublist(offset, offset + columns);
        final ratios = row
            .map(
              (p) =>
                  parts.length == 4 ? 1.0 : _postImageRatio(p).clamp(.8, 1.5),
            )
            .toList();
        final sum = ratios.fold<double>(0, (a, b) => a + b);
        final height = math.min(240.0, (available - gap * (columns - 1)) / sum);
        if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                tile(context, row[i], height * ratios[i], height),
              ],
            ],
          ),
        );
        offset += columns;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    },
  );
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
                  ReliableImage(
                    urls: [cover],
                    fit: BoxFit.cover,
                    fallback: const SizedBox.shrink(),
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
