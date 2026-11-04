import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import 'emoji.dart';

typedef Json = Map<String, dynamic>;

enum MessageKind { replies, likes, mentions }

class MessageBatch {
  const MessageBatch(this.items, this.hasMore, {this.cursor = ''});
  final List<Json> items;
  final bool hasMore;
  final String cursor;
}

Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
int number(dynamic value) => int.tryParse('$value') ?? 0;
bool flag(dynamic value) => value == true || number(value) == 1;
String forumName(Json forum) => firstText([forum['name'], forum['forum_name']]);
String forumCoverUrl(Json forum) => httpsImage(forum['header_image']);
String forumDescription(Json forum) {
  final description = plainText(forum['slogan']).trim();
  return description.isEmpty ? '吧主很懒，没有留下任何简介' : description;
}

String firstText(Iterable<dynamic> values, [String fallback = '']) => values
    .map((v) => v == null ? '' : '$v')
    .firstWhere((v) => v.isNotEmpty, orElse: () => fallback);
String author(Json user) => firstText([
  user['name_show'],
  user['show_nickname'],
  user['name'],
  user['user_name'],
], '吧友');

String forumRole(Json user) {
  final role = firstText([user['forum_role'], user['bawu_type']]);
  return switch (role) {
    'manager' || '吧主' || '大吧主' => '吧主',
    'assist' || '小吧主' => '小吧主',
    'voiceadmin' || '语音小编' => '语音小编',
    'videoadmin' || '视频小编' => '视频小编',
    'picadmin' || '图片小编' => '图片小编',
    _ => flag(user['is_bawu']) ? '吧务' : '',
  };
}

String postIp(Json post, Json user) {
  String label(dynamic raw) => raw is Map
      ? firstText([raw['ip_address'], raw['location'], raw['name']])
      : firstText([raw]);
  return firstText([
    label(post['ip_address']),
    label(post['ip_location']),
    label(user['ip_address']),
    label(user['ip_location']),
    RegExp(
      r'IP(?:属地)?\s*[:：]?\s*([^·|\n]+)',
      caseSensitive: false,
    ).firstMatch(plainText(post['footer']))?.group(1)?.trim(),
  ]).replaceFirst(RegExp(r'^IP(?:属地)?\s*[:：]?\s*', caseSensitive: false), '');
}

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

String threadForumName(Json thread) => firstText([
  thread['forum_name'],
  thread['fname'],
  object(thread['forum_info'])['forum_name'],
  object(thread['forum_info'])['name'],
  object(thread['forum'])['name'],
  object(thread['forum'])['forum_name'],
]);

String userKey(Json user, [Json thread = const {}]) {
  final id = firstText([user['id'], user['user_id'], thread['author_id']]);
  if (id.isNotEmpty && id != '0') return 'id:$id';
  final portrait = firstText([user['portrait'], user['user_portrait']]);
  if (portrait.isNotEmpty) return 'portrait:${portrait.split('?').first}';
  final name = firstText([user['name'], user['user_name']]);
  return name.isEmpty ? '' : 'name:$name';
}

String fullDate(dynamic value) {
  final timestamp = number(value);
  if (timestamp <= 0) return '时间未知';
  try {
    final date = DateTime.fromMillisecondsSinceEpoch(
      timestamp < 100000000000 ? timestamp * 1000 : timestamp,
    ).toLocal();
    String pad(int n) => '$n'.padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  } on RangeError {
    return '时间未知';
  }
}

String relativeDate(dynamic value, {DateTime? now}) {
  final timestamp = number(value);
  if (timestamp <= 0) return '时间未知';
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp < 100000000000 ? timestamp * 1000 : timestamp,
  );
  final elapsed = (now ?? DateTime.now()).difference(date);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}分钟前';
  if (elapsed.inDays < 1) return '${elapsed.inHours}小时前';
  if (elapsed.inDays < 7) return '${elapsed.inDays}天前';
  return fullDate(value);
}

int lastReplyTime(Json thread) => number(
  thread['last_time_int'] ?? thread['last_reply_time'] ?? thread['last_time'],
);

String commentTime(dynamic value, {DateTime? now}) {
  final timestamp = number(value);
  if (timestamp <= 0) return '时间未知';
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp < 100000000000 ? timestamp * 1000 : timestamp,
  ).toLocal();
  final current = now ?? DateTime.now();
  final elapsed = current.difference(date);
  final days = DateTime.utc(
    current.year,
    current.month,
    current.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  if (elapsed.isNegative || elapsed.inMinutes < 1) return '刚刚';
  if (days == 1) return '昨天';
  if (days == 2) return '前天';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}分钟前';
  if (elapsed.inHours < 24) return '${elapsed.inHours}小时前';
  String pad(int n) => '$n'.padLeft(2, '0');
  return '${date.year == current.year ? '' : '${date.year}-'}${pad(date.month)}-${pad(date.day)}';
}

String threadTimeLabel(Json thread, {bool latestReply = false}) {
  if (latestReply) {
    final time = lastReplyTime(thread);
    return time > 0 ? '最近回复 ${relativeDate(time)}' : '最近回复时间未知';
  }
  return '发布 ${relativeDate(thread['create_time'] ?? thread['time'])}';
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

class TiebaException implements Exception {
  const TiebaException(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
  @override
  String toString() => message;
}

bool unavailableForumMessage(String message) =>
    RegExp(r'本吧|该吧|此吧|这个吧|贴吧|吧已|吧被|吧不存在').hasMatch(message) &&
    RegExp(r'封禁|被封|封了|不存在|已关闭|已删除|暂停开放|暂不开放|停止服务|无法访问|已屏蔽').hasMatch(message) &&
    !RegExp(r'账号|帐号|用户被|您被|你被').hasMatch(message);

/// Only inspect the card itself: an ordinary post's author may be live too.
bool isLiveThread(Json thread) =>
    flag(thread['is_livepost']) ||
    flag(thread['is_live']) ||
    number(thread['live_id']) > 0 ||
    ['ala_info', 'live_info', 'livecard_info'].any((key) {
      final value = thread[key];
      return value is Map && value.isNotEmpty ||
          value is List && value.isNotEmpty;
    });

class TiebaPage {
  TiebaPage(this.data);
  final Json data;
  List<Json> get threads => objects(data['thread_list'])
      .map(
        (t) => <String, dynamic>{
          ...t,
          'id': firstText([t['tid'], t['id']]),
        },
      )
      .where(
        (t) =>
            !flag(t['is_tiebaplus_ad']) &&
            !flag(t['is_ad']) &&
            !isLiveThread(t) &&
            '${t['id'] ?? ''}'.isNotEmpty,
      )
      .toList();
  List<Json> get posts => objects(data['post_list']);
  List<Json> get replies => objects(data['subpost_list']);
  bool get hasMore {
    final page = object(data['page']);
    return page.containsKey('has_more')
        ? flag(page['has_more'])
        : number(page['current_page'] ?? page['cur_page']) <
              number(page['total_page']);
  }

  Map<String, Json> get users => {
    for (final user in objects(data['user_list'])) '${user['id']}': user,
  };
}

class SearchResult {
  const SearchResult(this.items, this.hasMore);
  final List<Json> items;
  final bool hasMore;
}
