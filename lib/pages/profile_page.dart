import '../widgets/app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/app_update.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../widgets/post_widgets.dart';
import 'login_page.dart';
import 'preferences_pages.dart';
import 'user_page.dart';
import 'my_content_page.dart';
import 'messages_page.dart';
import 'private_messages_page.dart';
import 'update_page.dart';
import 'theme_color_page.dart';

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
              title: Text(auth.isLoggedIn ? author(auth.user) : '游客模式'),
              subtitle: Text(auth.isLoggedIn ? '查看个人主页、关注和吧龄' : '点击登录，使用点赞、回复和收藏'),
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
                        Text('发帖'),
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
                        Text('回帖'),
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
                        Text('收藏'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const MessageEntry(),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('私信'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (!auth.isLoggedIn) {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              }
              if (!context.mounted || !auth.isLoggedIn) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivateMessagesPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('浏览历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
            ),
          ),
          ListenableBuilder(
            listenable: AppUpdate.instance,
            builder: (context, _) {
              final update = AppUpdate.instance;
              if (!update.available) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.system_update,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text('发现新版本 ${update.latest}'),
                  subtitle: Text(
                    update.downloading
                        ? '正在下载，可继续浏览'
                        : update.readyToInstall
                        ? '更新已下载，点击安装'
                        : '点击查看更新内容',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
                  ),
                ),
              );
            },
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

class MessageEntry extends StatefulWidget {
  const MessageEntry({super.key});
  @override
  State<MessageEntry> createState() => _MessageEntryState();
}

class _MessageEntryState extends State<MessageEntry>
    with WidgetsBindingObserver {
  final _api = TiebaApi();
  int _count = 0, _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthStore.instance.addListener(_refresh);
    AppUpdate.instance.check();
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      AppUpdate.instance.check();
    }
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    final account = AuthStore.instance.activeId;
    if (mounted) setState(() => _count = 0);
    if (!AuthStore.instance.isLoggedIn) return;
    try {
      final counts = await _api.messageCounts();
      if (mounted &&
          revision == _revision &&
          account == AuthStore.instance.activeId) {
        setState(
          () => _count =
              number(counts['replyme']) +
              number(counts['atme']) +
              number(counts['agreeme'] ?? counts['agree']),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthStore.instance.removeListener(_refresh);
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Badge.count(
      count: _count,
      isLabelVisible: _count > 0,
      child: const Icon(Icons.notifications_outlined),
    ),
    title: const Text('通知'),
    subtitle: const Text('回复我的 · 收到的赞 · @我的'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      if (!AuthStore.instance.isLoggedIn) {
        await Navigator.of(context)
            .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      }
      if (!context.mounted || !AuthStore.instance.isLoggedIn) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const MessagesPage()));
      if (mounted) _refresh();
    },
  );
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
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('游客模式'),
              subtitle: Text(auth.isGuest ? '当前模式 · 可浏览、搜索和查看帖子' : '暂不使用账号，保留已保存的账号'),
              trailing: auth.isGuest ? const Icon(Icons.check) : null,
              onTap: _busy || auth.isGuest
                  ? null
                  : () => _action(auth.enterGuestMode),
            ),
          ),
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
          ListenableBuilder(
            listenable: AppUpdate.instance,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('版本更新'),
              subtitle: Text(
                AppUpdate.instance.available
                    ? '发现新版本 ${AppUpdate.instance.latest}'
                    : '当前版本 ${AppUpdate.version}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
              ),
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
          ListenableBuilder(
            listenable: LocalStore.instance,
            builder: (context, _) => ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              ),
              title: const Text('背景颜色'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ThemeColorPage(background: true),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: LocalStore.instance,
            builder: (context, _) => ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: Color(LocalStore.instance.themeColor),
              ),
              title: const Text('强调色'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ThemeColorPage()),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: LocalStore.instance,
            builder: (context, _) => ListTile(
              leading: CircleAvatar(
                radius: 12,
                backgroundColor: Color(LocalStore.instance.buttonColor),
              ),
              title: const Text('按钮底色'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ThemeColorPage(button: true),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: LocalStore.instance,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.apartment_outlined),
              title: const Text('盖楼模式'),
              value: LocalStore.instance.buildingMode,
              onChanged: (value) async {
                try {
                  await LocalStore.instance.setBuildingMode(value);
                } catch (_) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showAppSnackBar(
                      const AppSnackBar(content: Text('设置保存失败，请重试')),
                    );
                }
              },
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
                    title: const Text('拉黑的人'),
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
            '拉黑在本机隐藏此人的帖子和评论，可在这里解除；吧名屏蔽影响首页。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于美滋滋'),
            subtitle: Text(AppUpdate.version),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: '美滋滋',
              applicationVersion: AppUpdate.version,
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
    appBar: AppBar(title: Text(forums ? '屏蔽的吧' : '拉黑的人')),
    body: ListenableBuilder(
      listenable: LocalStore.instance,
      builder: (context, _) {
        final store = LocalStore.instance;
        final entries = (forums ? store.blockedForums : store.blockedUsers)
            .entries
            .toList()
            .reversed
            .toList();
        if (entries.isEmpty) return const Center(child: Text('暂无屏蔽内容'));
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              title: Text('${entry.value}${forums ? '吧' : ''}'),
              trailing: TextButton(
                child: Text(forums ? '解除屏蔽' : '解除拉黑'),
                onPressed: () async {
                  try {
                    await store.unblock(entry.key, forum: forums);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showAppSnackBar(
                        const AppSnackBar(content: Text('保存失败，请重试')),
                      );
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
