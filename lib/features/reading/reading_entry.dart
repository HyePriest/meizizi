import '../../data/models.dart';

/// One immutable decision for entry: explicit target, compatible cache, then
/// saved position. Async loading never reads a mutable pending target.
class ReadingEntry {
  const ReadingEntry({
    this.cache,
    this.post,
    this.reply,
    this.delta = 0,
    this.page,
    this.hot = false,
    this.descending = false,
    this.onlyAuthor = false,
  });

  final Json? cache;
  final String? post, reply;
  final double delta;
  final int? page;
  final bool hot, descending, onlyAuthor;
  String? get target => reply ?? post;

  factory ReadingEntry.resolve({
    required bool building,
    required bool nested,
    String? targetPost,
    String? targetReply,
    Json? cache,
    Json position = const {},
  }) {
    String? nonEmpty(String? value) =>
        value == null || value.isEmpty ? null : value;
    final post = nonEmpty(targetPost);
    final reply = nonEmpty(targetReply);
    if (post != null || reply != null) {
      return ReadingEntry(post: post, reply: reply);
    }
    final compatibleCache =
        cache != null && flag(cache['building']) == building;
    final source = compatibleCache ? cache : position;
    if (!compatibleCache && !nested && flag(source['building']) != building) {
      return const ReadingEntry();
    }
    final hot = !nested && flag(source['hot']);
    final descending = !nested && !hot && flag(source['descending']);
    final id = nonEmpty(firstText([source['post']]));
    return ReadingEntry(
      cache: compatibleCache ? cache : null,
      post: nested ? null : id,
      reply: nested ? id : null,
      delta: (source['delta'] as num?)?.toDouble() ?? 0,
      page: (hot || descending) && number(source['page']) > 0
          ? number(source['page'])
          : null,
      hot: hot,
      descending: descending,
      onlyAuthor: flag(source['only_author']),
    );
  }
}
