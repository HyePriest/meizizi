import 'package:html/parser.dart' as html;

typedef Json = Map<String, dynamic>;
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Json> objects(dynamic value) =>
    value is List ? value.map(object).toList() : [];
int number(dynamic value) => int.tryParse('$value') ?? 0;
bool flag(dynamic value) => value == true || number(value) == 1;
String firstText(Iterable<dynamic> values, [String fallback = '']) => values
    .map((v) => v == null ? '' : '$v')
    .firstWhere((v) => v.isNotEmpty, orElse: () => fallback);
String author(Json user) => firstText([
  user['name_show'],
  user['show_nickname'],
  user['name'],
  user['user_name'],
], '吧友');
String plainText(dynamic value) =>
    html.parseFragment('${value ?? ''}').text ?? '';

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

String httpsImage(dynamic value) {
  final uri = Uri.tryParse('${value ?? ''}');
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
