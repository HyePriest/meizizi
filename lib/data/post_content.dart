/// Turns Tieba post bodies (rich-text parts or HTML) into display parts, and
/// extracts images, videos and avatar addresses from them.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'emoji.dart';
import 'json_values.dart';

final _plainTextCache = <String, String>{};

String plainText(dynamic value) {
  final source = '${value ?? ''}';
  final cached = _plainTextCache.remove(source);
  if (cached != null) {
    _plainTextCache[source] = cached;
    return cached;
  }
  final text = html.parseFragment(source).text ?? '';
  // Keep small, frequently rebuilt labels; never retain whole long posts.
  if (source.length <= 2048) {
    _plainTextCache[source] = text;
    if (_plainTextCache.length > 256) {
      _plainTextCache.remove(_plainTextCache.keys.first);
    }
  }
  return text;
}

List<Json> contentParts(dynamic content) {
  if (content is List) {
    return objects(content)
        .expand(
          (part) => part.containsKey('post_content')
              ? contentParts(part['post_content'])
              : number(part['type']) == 0 &&
                    RegExp(
                      r'<(?:img|br)\b',
                      caseSensitive: false,
                    ).hasMatch('${part['text'] ?? ''}')
              ? contentParts(part['text'])
              : number(part['type']) == 0 && part['text'] is String
              ? expandTextEmoji(part['text'] as String)
              : [part],
        )
        .toList();
  }
  if (content is Map) {
    return contentParts(
      content['post_content'] ?? content['content'] ?? content['list'],
    );
  }
  if (content is! String || content.isEmpty) return [];
  final fragment = html.parseFragment(content);
  final parts = <Json>[];
  void visit(dom.Node node) {
    if (node is dom.Text) {
      if (node.text.isNotEmpty) parts.addAll(expandTextEmoji(node.text));
    } else if (node is dom.Element && node.localName == 'img') {
      final src = firstText([
        node.attributes['data-original'],
        node.attributes['data-src'],
        node.attributes['src'],
      ]);
      final label = firstText([
        node.attributes['alt'],
        node.attributes['title'],
      ]);
      final emoticon = isEmojiImage(
        src,
        label: label,
        smileyClass: node.classes.contains('BDE_Smiley'),
      );
      parts.add({'type': emoticon ? 2 : 3, 'src': src, 'c': label});
    } else if (node is dom.Element && node.localName == 'br') {
      parts.add({'type': 0, 'text': '\n'});
    } else {
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  for (final node in fragment.nodes) {
    visit(node);
  }
  return parts;
}

List<Json> threadImages(Json thread) {
  List<Json> pictures(dynamic value) => value is List
      ? value
            .map(
              (v) => v is String
                  ? <String, dynamic>{'src': v, 'type': 3}
                  : object(v),
            )
            .toList()
      : [];
  final media = pictures(thread['media']);
  final candidates = [
    if (media.isNotEmpty)
      ...media
    else ...[
      ...pictures(thread['image_list']),
      ...pictures(thread['pic_list']),
      ...pictures(thread['pic_info']),
      ...contentParts(thread['rich_abstract']),
      ...contentParts(thread['abstract']),
      ...contentParts(thread['content']),
    ],
  ];
  final seen = <String>{};
  final images = <Json>[];
  for (final part in candidates) {
    if ([2, 5, 10].contains(number(part['type'])) || part['type'] == 'video') {
      continue;
    }
    final url = httpsImage(
      firstText([
        part['small_pic'],
        part['big_pic'],
        part['cdn_src'],
        part['src_pic'],
        part['origin_pic'],
        part['origin_src'],
        part['src'],
      ]),
    );
    final segments = Uri.tryParse(url)?.pathSegments ?? [];
    if (url.isNotEmpty && seen.add(segments.isEmpty ? url : segments.last)) {
      images.add({
        'thumbnail': url,
        'original': httpsImage(
          firstText([
            part['origin_pic'],
            part['origin_src'],
            part['big_pic'],
            part['src_pic'],
          ], url),
        ),
      });
    }
  }
  return images;
}

String videoSource(Json info) => httpsImage(
  firstText([info['video_url'], info['video_src'], info['link'], info['text']]),
);

String videoThumbnail(Json info) => httpsImage(
  firstText([
    info['thumbnail_url'],
    info['small_thumbnail_url'],
    info['first_frame_thumbnail'],
    info['thumbnail'],
    info['cover_url'],
    info['cover'],
    info['src'],
    info['cdn_src'],
  ]),
);

Json threadVideo(Json thread) {
  final info = object(thread['video_info']);
  if (videoSource(info).isNotEmpty || videoThumbnail(info).isNotEmpty) {
    return info;
  }
  for (final part in [
    ...objects(thread['media']),
    ...contentParts(thread['rich_abstract']),
    ...contentParts(thread['abstract']),
    ...contentParts(thread['content']),
  ]) {
    if (number(part['type']) == 5 || part['type'] == 'video') return part;
  }
  return {};
}

String httpsImage(dynamic value) {
  if (value is Map) {
    for (final key in [
      'url',
      'src',
      'origin_src',
      'original',
      'big',
      'small',
    ]) {
      final url = httpsImage(value[key]);
      if (url.isNotEmpty) return url;
    }
    return '';
  }
  var raw = '${value ?? ''}'.trim().replaceAll('&amp;', '&');
  if (raw.toLowerCase().startsWith('http%')) {
    try {
      raw = Uri.decodeFull(raw);
    } catch (_) {
      return '';
    }
  }
  final uri = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return '';
  }
  return uri.replace(scheme: 'https').toString();
}

String avatarUrl(Json user) {
  final portrait = firstText([
    user['portrait'],
    user['portraith'],
    user['user_portrait'],
    user['avatar'],
  ]);
  final direct = httpsImage(portrait);
  if (direct.isNotEmpty || portrait.isEmpty) return direct;
  return Uri.https(
    'himg.bdimg.com',
    '/sys/portrait/item/${portrait.split('?').first}',
  ).toString();
}
