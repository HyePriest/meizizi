import 'json_values.dart';
import 'post_content.dart';

export 'json_values.dart';
export 'post_content.dart';
export 'time_labels.dart';

enum MessageKind { replies, likes, mentions }

class MessageBatch {
  const MessageBatch(this.items, this.hasMore, {this.cursor = ''});
  final List<Json> items;
  final bool hasMore;
  final String cursor;
}

String forumName(Json forum) => firstText([forum['name'], forum['forum_name']]);
String forumCoverUrl(Json forum) => httpsImage(forum['header_image']);
String forumDescription(Json forum) {
  final description = plainText(forum['slogan']).trim();
  return description.isEmpty ? '吧主很懒，没有留下任何简介' : description;
}

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

String threadForumName(Json thread) => firstText([
  thread['forum_name'],
  thread['fname'],
  object(thread['forum_info'])['forum_name'],
  object(thread['forum_info'])['name'],
  object(thread['forum'])['name'],
  object(thread['forum'])['forum_name'],
]);

/// A home feed card that recommends one comment rather than a thread
/// (`thread_type` 81). Its `id` is a feed-only number that no thread page
/// knows; the real thread is `origin_thread_info.tid` and the comment's floor
/// is `post_id`. Returns null for ordinary threads.
({String threadId, String postId, String threadTitle})? feedComment(Json item) {
  final origin = object(item['origin_thread_info']);
  final threadId = firstText([origin['tid'], origin['thread_id']]);
  final postId = firstText([item['post_id'], item['pid']]);
  if (threadId.isEmpty || threadId == '0' || postId.isEmpty || postId == '0') {
    return null;
  }
  return (
    threadId: threadId,
    postId: postId,
    threadTitle: firstText([
      origin['title'],
    ], firstText([item['title']]).replaceFirst(RegExp(r'^回复[:：]'), '')),
  );
}

String userKey(Json user, [Json thread = const {}]) {
  final id = firstText([user['id'], user['user_id'], thread['author_id']]);
  if (id.isNotEmpty && id != '0') return 'id:$id';
  final portrait = firstText([user['portrait'], user['user_portrait']]);
  if (portrait.isNotEmpty) return 'portrait:${portrait.split('?').first}';
  final name = firstText([user['name'], user['user_name']]);
  return name.isEmpty ? '' : 'name:$name';
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
