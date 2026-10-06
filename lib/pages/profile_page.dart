import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'login_page.dart';
import 'preferences_pages.dart';
import 'user_page.dart';
import 'my_content_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthStore.instance,
    builder: (context, _) {
      final auth = AuthStore.instance;
      void login() =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
      void content(MyContent kind) {
        if (!auth.isLoggedIn) {
          login();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => MyContentPage(kind: kind)),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: UserAvatar(user: auth.user, size: 52),
              title: Text(auth.isLoggedIn ? author(auth.user) : '点击登录'),
              subtitle: Text(auth.isLoggedIn ? '查看我的主页、关注和吧龄' : '登录后查看个人内容'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                if (auth.isLoggedIn) {
                  openUser(context, auth.user);
                } else {
                  login();
                }
              },
            ),
          ),
          Card(
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => content(MyContent.threads),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined),
                        SizedBox(height: 6),
                        Text('我的发帖'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => content(MyContent.replies),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.reply),
                        SizedBox(height: 6),
                        Text('我的回帖'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => content(MyContent.saved),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark_outline),
                        SizedBox(height: 6),
                        Text('我的收藏'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('浏览历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
            ),
          ),
        ],
      );
    },
  );
}

class SettingsContent extends StatefulWidget {
  const SettingsContent({super.key});
  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  bool _busy = false;
  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is TiebaException ? e.message : '账号操作失败，请重试'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _action(() async {
    await AuthStore.instance.prepareNewLogin();
    if (mounted) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthStore.instance,
    builder: (context, _) {
      final auth = AuthStore.instance;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('账号管理', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('可保存多个账号，点击账号直接切换。'),
          const SizedBox(height: 12),
          for (final account in auth.accounts)
            Card(
              child: ListTile(
                leading: UserAvatar(user: object(account['user']), size: 44),
                title: Text(author(object(account['user']))),
                subtitle: Text(
                  account['id'] == auth.activeId ? '当前账号' : '点击切换',
                ),
                onTap: _busy
                    ? null
                    : () =>
                          _action(() => auth.switchAccount('${account['id']}')),
                trailing: IconButton(
                  tooltip: '从本机移除账号',
                  onPressed: _busy
                      ? null
                      : () => _action(
                          () => auth.removeAccount('${account['id']}'),
                        ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.person_add_outlined),
            label: Text(_busy ? '处理中' : '添加账号'),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('浏览历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
            ),
          ),
          Text('内容偏好', style: Theme.of(context).textTheme.titleLarge),
          ListenableBuilder(
            listenable: LocalStore.instance,
            builder: (context, _) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.filter_alt_outlined),
                    title: const Text('按吧名关键词屏蔽'),
                    subtitle: Text(
                      '${LocalStore.instance.forumKeywords.length} 个关键词',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const KeywordPage(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('屏蔽的吧'),
                    subtitle: Text(
                      '${LocalStore.instance.blockedForums.length} 个',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BlockedPage(forums: true),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('屏蔽的人'),
                    subtitle: Text(
                      '${LocalStore.instance.blockedUsers.length} 人',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BlockedPage(forums: false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            '屏蔽仅影响本机首页；你仍可以主动搜索和进入对应的吧。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于贴吧'),
            subtitle: const Text('0.7.2'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '贴吧',
              applicationVersion: '0.7.2',
              children: [const Text('Flutter 第三方贴吧客户端。')],
            ),
          ),
        ],
      );
    },
  );
}

class BlockedPage extends StatelessWidget {
  const BlockedPage({super.key, required this.forums});
  final bool forums;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(forums ? '屏蔽的吧' : '屏蔽的人')),
    body: ListenableBuilder(
      listenable: LocalStore.instance,
      builder: (context, _) {
        final store = LocalStore.instance;
        final entries = (forums ? store.blockedForums : store.blockedUsers)
            .entries
            .toList();
        if (entries.isEmpty) return const Center(child: Text('暂无屏蔽内容'));
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              title: Text('${entry.value}${forums ? '吧' : ''}'),
              trailing: TextButton(
                child: const Text('解除屏蔽'),
                onPressed: () async {
                  try {
                    await store.unblock(entry.key, forum: forums);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
                    }
                  }
                },
              ),
            );
          },
        );
      },
    ),
  );
}
