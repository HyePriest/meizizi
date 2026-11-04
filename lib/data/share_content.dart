import 'platform_session.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'emoji.dart';
import 'share_image.dart';

String contentSummary(dynamic content) => contentParts(content)
    .map((part) {
      final type = number(part['type']);
      if (type == 52) return '';
      if (type == 2) return resolveEmoji(part).fallback;
      if (type == 3 || type == 20) return '[图片]';
      if (type == 5) return '[视频]';
      if (type == 10) return '[语音]';
      return plainText(part['text']);
    })
    .join()
    .trim()
    .replaceFirst(RegExp(r'^[:：]\s*'), '');

class ShareContent {
  const ShareContent({
    required this.title,
    required this.url,
    required this.text,
    this.forum = '',
    this.imageData = const {},
    this.isComment = false,
    this.isForum = false,
  });
  final String title, url, text;
  final String forum;
  final Json imageData;
  final bool isComment;
  final bool isForum;
  static bool _sharing = false;
  static const channel = PlatformSession();

  factory ShareContent.forForum(String name, Json data) {
    final url = Uri.https('tieba.baidu.com', '/f', {'kw': name}).toString();
    return ShareContent(
      title: '$name吧',
      forum: name,
      url: url,
      isForum: true,
      imageData: Map<String, dynamic>.unmodifiable(data),
      text: ['$name吧', forumDescription(data), url].join('\n'),
    );
  }

  Future<void> shareLink() =>
      channel.invokeMethod<void>('shareText', {'title': title, 'text': text});

  Future<Uint8List> renderPoster({String? headerImage}) => renderForumPoster(
    name: forum,
    url: url,
    data: {...imageData, if (headerImage != null) 'header_image': headerImage},
  );

  factory ShareContent.post({
    required String threadId,
    required String title,
    String forum = '',
    String postId = '',
    Json? comment,
    Json? post,
  }) {
    final url =
        Uri.https(
              'tieba.baidu.com',
              '/p/$threadId',
              postId.isEmpty || postId == '0' ? null : {'pid': postId},
            )
            .replace(fragment: postId.isEmpty || postId == '0' ? null : postId)
            .toString();
    final heading = title.isEmpty ? '贴吧帖子' : title;
    var excerpt = comment == null ? '' : contentSummary(comment['content']);
    if (excerpt.length > 400) {
      var end = 400;
      if (excerpt.codeUnitAt(end - 1) >= 0xd800 &&
          excerpt.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      excerpt = '${excerpt.substring(0, end)}…';
    }
    return ShareContent(
      title: heading,
      forum: forum,
      imageData: comment ?? post ?? const {},
      isComment: comment != null,
      url: url,
      text: [
        heading,
        if (forum.isNotEmpty) '$forum吧',
        if (comment != null && excerpt.isNotEmpty)
          '${author(object(comment['author']))}：$excerpt',
        url,
      ].join('\n'),
    );
  }

  Future<void> share() async {
    if (_sharing) return;
    _sharing = true;
    try {
      final bytes = isForum
          ? await renderPoster()
          : await renderShareImage(
              title: title,
              forum: forum,
              url: url,
              data: imageData,
              comment: isComment,
            );
      await channel.invokeMethod<void>('shareImage', {
        'bytes': bytes,
        'title': title,
        'url': url,
      });
    } finally {
      _sharing = false;
    }
  }

  Future<void> copyLink() => Clipboard.setData(ClipboardData(text: url));
}
