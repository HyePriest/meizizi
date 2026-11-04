import 'dart:convert';

import 'models.dart';

String decodeForumHeaderImage(Json data) {
  for (final image in objects(object(data['activityhead'])['head_imgs'])) {
    final url = httpsImage(image['img_url']);
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) return url;
  }
  return '';
}

class ForumSection {
  const ForumSection({
    required this.id,
    required this.name,
    required this.type,
  });
  final int id, type;
  final String name;
}

List<ForumSection> forumSections(Json data) {
  final seen = <int>{};
  return [
    for (final tab in objects(object(data['nav_tab_info'])['tab']))
      if (number(tab['tab_type']) == 15 &&
          number(tab['tab_id']) > 0 &&
          firstText([tab['tab_name']]).isNotEmpty &&
          seen.add(number(tab['tab_id'])))
        ForumSection(
          id: number(tab['tab_id']),
          name: firstText([tab['tab_name']]),
          type: number(tab['tab_type']),
        ),
  ];
}

/// Converts the two observed FRS formats to the reader's existing thread model.
class ForumThreads {
  const ForumThreads(this.threads, {this.issue});
  final List<Json> threads;
  final String? issue;
}

ForumThreads decodeForumThreads(Json data) {
  final threads = <Json>[];
  final ids = <String>{};
  var malformed = false;
  var filteredLive = false;
  void add(Json thread) {
    if (isLiveThread(thread)) {
      filteredLive = true;
      return;
    }
    if (flag(thread['is_ad']) || flag(thread['is_tiebaplus_ad'])) return;
    final id = firstText([thread['tid'], thread['id']]);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      malformed = true;
      return;
    }
    if (ids.add(id)) threads.add({...thread, 'id': id});
  }

  final classic = data['thread_list'];
  final cards = object(data['page_data'])['feed_list'];
  final recognized = classic is List || cards is List;
  if (classic is List) {
    for (final thread in classic) {
      if (thread is Map) {
        add(object(thread));
      } else {
        malformed = true;
      }
    }
  } else if (classic != null) {
    malformed = true;
  }
  if (cards is List) {
    for (final raw in cards) {
      final card = object(raw);
      switch (card['layout']) {
        case 'feed':
          final feed = object(card['feed']);
          final business = _pairs(feed['business_info']);
          if (isLiveThread(feed) || isLiveThread(business)) {
            filteredLive = true;
            continue;
          }
          if (flag(business['is_ad']) || flag(business['is_tiebaplus_ad'])) {
            continue;
          }
          final components = <String, Json>{
            for (final component in objects(feed['components']))
              if (component['component'] is String)
                component['component'] as String: object(
                  component[component['component']],
                ),
          };
          final social = components['feed_social'] ?? {};
          final head = components['feed_head'] ?? {};
          final route = _route(feed['schema']);
          final title = firstText([
            business['title'],
            _richText(components['feed_title']?['data']),
          ]);
          if (title.isEmpty) {
            malformed = true;
            continue;
          }
          add({
            'tid': firstText([
              business['thread_id'],
              social['tid'],
              route['tid'],
            ]),
            'title': title,
            'abstract': firstText([
              business['abstract'],
              _richText(components['feed_abstract']?['data']),
            ]),
            'author_id': business['user_id'],
            'author': _author(head, id: business['user_id']),
            'forum_name': firstText([
              business['forum_name'],
              route['forumName'],
            ]),
            'fid': business['forum_id'] ?? social['fid'],
            'create_time': business['create_time'],
            // A creation time must not be presented as the last reply time.
            if (business['last_reply_time'] != null)
              'last_reply_time': business['last_reply_time'],
            'reply_num': social['comment_num'],
            'agree': social['agree'],
            'first_post_id': social['first_post_id'],
            'pic_list': [
              for (final pic in objects(components['feed_pic']?['pics']))
                {
                  'src': pic['small_pic_url'],
                  'origin_src': pic['origin_pic_url'] ?? pic['big_pic_url'],
                  'width': pic['width'],
                  'height': pic['height'],
                },
            ],
          });
          // Preserve readable text when an as-yet unsupported media component
          // appears, but report the incomplete card instead of hiding it.
          if (components.keys.any(
            (key) => !{
              'feed_head',
              'feed_title',
              'feed_abstract',
              'feed_pic',
              'feed_social',
            }.contains(key),
          )) {
            malformed = true;
          }
        case 'frs_top_thread_card':
          final components = object(card['frs_top_thread_card'])['components'];
          if (components is! List || components.isEmpty) malformed = true;
          for (final component in objects(components)) {
            final top = object(component['frs_top_thread']);
            final social = object(top['author_social']);
            final route = _route(top['scheme']);
            final title = _richText(top['title']);
            if (title.isEmpty) {
              malformed = true;
              continue;
            }
            final user = _author(social);
            add({
              'tid': social['tid'] ?? route['tid'],
              'title': title,
              'is_top': 1,
              'abstract': _richText(object(top['pic_abstract'])['abstract']),
              'author': user,
              'author_id': user['id'],
              'reply_num': social['comment_num'],
              'agree': social['agree'],
              'fid': social['fid'],
              'forum_name': route['forumName'],
            });
          }
        case 'hot_topic_card':
          // A topic entry is navigation, not a post.
          break;
        default:
          malformed = true;
      }
    }
  } else if (cards != null) {
    malformed = true;
  }
  // An explicit empty list without another page is a valid empty result.
  // Missing lists, damaged cards, and empty pages advertising more content
  // must never be mistaken for a forum with no posts.
  final emptyWithMore =
      threads.isEmpty && !filteredLive && TiebaPage(data).hasMore;
  return ForumThreads(
    threads,
    issue: !recognized
        ? 'missing_thread_list'
        : malformed
        ? 'unrecognized_thread_cards'
        : emptyWithMore
        ? 'empty_page_with_more'
        : null,
  );
}

Json _pairs(dynamic value) => {
  for (final pair in objects(value))
    if (pair['key'] is String) pair['key'] as String: pair['value'],
};

Json _route(dynamic value) {
  if (value is! String) return {};
  try {
    final params = Uri.parse(value).queryParameters['params'];
    return params == null
        ? {}
        : object(object(jsonDecode(params))['pageParams']);
  } on FormatException {
    return {};
  }
}

String _richText(dynamic value) => objects(value).map((part) {
  // Type 6 is the decorative "置顶" label, not part of the title.
  if (number(part['type']) == 6) return '';
  return firstText([
    object(part['text_info'])['text'],
    object(part['emoji_info'])['c'],
  ]);
}).join();

Json _author(Json head, {dynamic id}) {
  final main = objects(head['main_data']);
  final image = object(head['image_data']);
  final route = _route(image['schema']);
  final user = <String, dynamic>{
    'id': id ?? route['uid'],
    'portrait': image['img_url'],
    'name_show': firstText([
      for (final part in main)
        if (number(part['type']) == 1) object(part['text'])['text'],
    ]),
  };
  for (final part in main) {
    final custom = object(part['custom']);
    if (custom['style'] == 'forum_level' && custom['data'] is String) {
      try {
        final level = object(jsonDecode(custom['data'] as String));
        user.addAll({
          'level_id': level['level_id'],
          'level_name': level['level_name'],
        });
      } on FormatException {
        // This badge is optional; it does not affect the post itself.
      }
    }
  }
  return user;
}
