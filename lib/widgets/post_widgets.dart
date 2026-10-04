import 'package:flutter/material.dart';

import '../data/models.dart';
import '../pages/image_page.dart';

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
  const UserHeader({super.key, required this.user, required this.subtitle});
  final Json user;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      UserAvatar(user: user),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              author(user),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    ],
  );
}

String emojiUrl(Json part) {
  for (final value in [part['src'], part['text'], part['c']]) {
    final direct = httpsImage(value);
    if (direct.isNotEmpty) return direct;
    final match = RegExp(r'image_emoticon(\d*)').firstMatch('${value ?? ''}');
    if (match != null) {
      final id = match.group(1)!;
      return 'https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon${id == '1' ? '' : id}.png';
    }
  }
  return '';
}

class PostContent extends StatelessWidget {
  const PostContent({super.key, required this.parts});
  final List<Json> parts;
  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final spans = <InlineSpan>[];
    void flush() {
      if (spans.isEmpty) return;
      widgets.add(
        SelectionArea(
          child: Text.rich(
            TextSpan(children: List.of(spans)),
            style: const TextStyle(fontSize: 16, height: 1.65),
          ),
        ),
      );
      spans.clear();
    }

    for (final part in parts) {
      final type = number(part['type']);
      if (type == 3 ||
          (type == 4 && '${part['origin_src'] ?? ''}'.isNotEmpty)) {
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImagePage(
                    url: httpsImage(
                      firstText([
                        part['origin_src'],
                        part['big_cdn_src'],
                        part['cdn_src'],
                        part['src'],
                      ]),
                    ),
                  ),
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
    final url = httpsImage(
      firstText([
        part['big_cdn_src'],
        part['origin_src'],
        part['cdn_src'],
        part['src'],
      ]),
    );
    if (url.isEmpty) return const Text('[图片地址不可用]');
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Padding(padding: EdgeInsets.all(24), child: Text('图片加载失败')),
    );
  }
}
