import 'package:flutter/material.dart';

import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'reading_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.word});
  final String word;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _api = TiebaApi();
  late final TextEditingController _query;
  List<Json> _items = [];
  bool _forums = true, _busy = false, _more = false;
  int _page = 0, _revision = 0;
  late String _word;
  String? _error;
  @override
  void initState() {
    super.initState();
    _word = widget.word;
    _query = TextEditingController(text: _word);
    _load(reset: true);
  }

  @override
  void dispose() {
    _revision++;
    _api.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_word.isEmpty || (_busy && !reset)) return;
    final revision = ++_revision;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) _items = [];
    });
    try {
      final result = await _api.search(_word, page, forums: _forums);
      if (!mounted || revision != _revision) return;
      setState(() {
        final ids = _items
            .map((p) => '${p['id'] ?? p['pid'] ?? p['tid']}')
            .toSet();
        _items.addAll(
          result.items.where(
            (p) => ids.add('${p['id'] ?? p['pid'] ?? p['tid']}'),
          ),
        );
        _page = page;
        _more = result.hasMore;
      });
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is TiebaException ? e.message : '搜索失败，请检查网络后重试',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  void _search() {
    final word = _query.text.trim();
    if (word.isEmpty) return;
    _word = word;
    FocusScope.of(context).unfocus();
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        controller: _query,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: const InputDecoration(
          hintText: '搜索吧或帖子',
          border: InputBorder.none,
        ),
      ),
      actions: [
        IconButton(
          onPressed: _search,
          icon: const Icon(Icons.search),
          tooltip: '搜索',
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('吧'),
                icon: Icon(Icons.forum_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('帖子'),
                icon: Icon(Icons.article_outlined),
              ),
            ],
            selected: {_forums},
            onSelectionChanged: (values) {
              if (_forums != values.first) {
                _forums = values.first;
                _load(reset: true);
              }
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length + 1,
            itemBuilder: (context, index) {
              if (index == _items.length) {
                if (_busy) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_error != null) {
                  return Column(
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: () => _load(reset: _items.isEmpty),
                        child: const Text('重试'),
                      ),
                    ],
                  );
                }
                if (_items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('没有找到相关结果，请换个关键词。'),
                  );
                }
                return Center(
                  child: _more
                      ? TextButton(onPressed: _load, child: const Text('加载更多'))
                      : const Text('没有更多结果了'),
                );
              }
              final item = _items[index];
              if (_forums) {
                return Card(
                  child: ListTile(
                    leading: UserAvatar(user: {'avatar': item['img']}),
                    title: Text('${item['name']}吧'),
                    subtitle: Text(
                      '${plainText(item['brief'])}\n${item['member'] ?? 0} 人关注 · ${item['post'] ?? 0} 个帖子',
                    ),
                    isThreeLine: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReadingPage(forum: '${item['name']}'),
                      ),
                    ),
                  ),
                );
              }
              final user = object(item['user']);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingPage(
                        threadId: '${item['tid']}',
                        title: plainText(item['title']),
                        forum: '${item['forum_name'] ?? ''}',
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserHeader(
                          user: user,
                          subtitle:
                              '发布 ${fullDate(item['create_time'] ?? item['time'])}',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          plainText(item['title']),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plainText(item['content']),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${item['forum_name'] ?? ''}吧 · ${item['post_num'] ?? 0} 条回复',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
