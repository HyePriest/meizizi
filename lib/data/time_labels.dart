/// Date and time labels shown next to threads, posts and comments.
library;

import 'json_values.dart';

/// Tieba timestamps arrive in seconds or milliseconds; small values are seconds.
DateTime _timestampDate(int timestamp) => DateTime.fromMillisecondsSinceEpoch(
  timestamp < 100000000000 ? timestamp * 1000 : timestamp,
);

String fullDate(dynamic value) {
  final timestamp = number(value);
  if (timestamp <= 0) return '时间未知';
  try {
    final date = _timestampDate(timestamp).toLocal();
    String pad(int n) => '$n'.padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
  } on RangeError {
    return '时间未知';
  }
}

String relativeDate(dynamic value, {DateTime? now}) {
  final timestamp = number(value);
  if (timestamp <= 0) return '时间未知';
  final date = _timestampDate(timestamp);
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
  final date = _timestampDate(timestamp).toLocal();
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
