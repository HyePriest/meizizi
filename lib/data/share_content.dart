import 'package:flutter/services.dart';

import 'models.dart';
import 'emoji.dart';

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
  });
  final String title, url, text;
  static const channel = MethodChannel('com.jknl.tieba/session');

  factory ShareContent.post({
    required String threadId,
    required String title,
    String forum = '',
    String postId = '',
    Json? comment,
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

  Future<void> share() =>
      channel.invokeMethod<void>('shareText', {'title': title, 'text': text});
  Future<void> copyLink() => Clipboard.setData(ClipboardData(text: url));
}
