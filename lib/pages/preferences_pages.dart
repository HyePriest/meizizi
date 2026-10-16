import '../widgets/app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import 'reading_page.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('浏览历史'),
      actions: [
        TextButton(
          onPressed: () async {
            final clear = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('清空浏览历史？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('清空'),
                  ),
                ],
              ),
            );
            if (clear == true) await LocalStore.instance.clearHistory();
          },
          child: const Text('清空'),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: LocalStore.instance,
      builder: (context, _) {
        final store = LocalStore.instance;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (store.recent.isNotEmpty) ...[
              Text('最近浏览的吧', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 8,
                children: [
                  for (final forum in store.recent)
                    ActionChip(
                      label: Text('$forum吧'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReadingPage(forum: forum),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text('最近浏览的帖子', style: Theme.of(context).textTheme.titleMedium),
            if (store.history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('浏览过的帖子会记录在这里'),
              ),
            for (final entry in store.history)
              ListTile(
                title: Text(
                  firstText([entry['title']], '查看帖子'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${entry['forum']}吧 · 浏览于${relativeDate(entry['viewed_at'])}',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingPage(
                      threadId: '${entry['id']}',
                      title: '${entry['title']}',
                      forum: '${entry['forum']}',
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class KeywordPage extends StatefulWidget {
  const KeywordPage({super.key});
  @override
  State<KeywordPage> createState() => _KeywordPageState();
}

class _KeywordPageState extends State<KeywordPage> {
  final _text = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save([String? word]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await LocalStore.instance.addForumKeyword(word ?? _text.text);
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('按吧名关键词屏蔽')),
    body: ListenableBuilder(
      listenable: LocalStore.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('首页会隐藏吧名包含这些关键词的帖子。比如“大学”可屏蔽各个大学吧，“学院”可覆盖学院吧。'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: '吧名关键词',
                    hintText: '例如：大学',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('添加'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final word in ['大学', '学院'])
                ActionChip(
                  label: Text('添加“$word”'),
                  onPressed: _busy ? null : () => _save(word),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final word in LocalStore.instance.forumKeywords)
            ListTile(
              title: Text(word),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await LocalStore.instance.removeForumKeyword(word);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showAppSnackBar(
                        const AppSnackBar(content: Text('保存失败，请重试')),
                      );
                    }
                  }
                },
                child: const Text('移除'),
              ),
            ),
          if (LocalStore.instance.forumKeywords.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('尚未添加关键词')),
        ],
      ),
    ),
  );
}
