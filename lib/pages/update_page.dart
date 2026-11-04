import 'package:flutter/material.dart';

import 'dart:io';

import '../data/app_update.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  @override
  void initState() {
    super.initState();
    AppUpdate.instance.check();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('版本更新')),
    body: ListenableBuilder(
      listenable: AppUpdate.instance,
      builder: (context, _) {
        final update = AppUpdate.instance;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '当前版本 ${AppUpdate.version.isEmpty ? '读取中…' : AppUpdate.version}',
            ),
            const SizedBox(height: 16),
            Text(
              Platform.isWindows
                  ? 'Windows 桌面版'
                  : update.checking
                  ? '正在检查更新…'
                  : update.checkError != null
                  ? '暂时无法确认最新版本'
                  : update.available
                  ? '发现新版本 ${update.latest}'
                  : update.latest.isEmpty
                  ? '查看是否有新版本'
                  : '已是最新版本',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (update.latest.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('公开发布版本 ${update.latest}'),
            ],
            if (update.checkError != null || update.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  [
                    update.checkError,
                    update.error,
                  ].whereType<String>().join('\n'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            if (update.available)
              FilledButton.icon(
                onPressed: update.downloading ? null : update.install,
                icon: const Icon(Icons.system_update),
                label: Text(
                  update.downloading
                      ? '正在下载更新，可继续浏览…'
                      : update.readyToInstall
                      ? '安装 ${update.latest}'
                      : '下载 ${update.latest}',
                ),
              ),
            if (Platform.isWindows)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('请在项目发布页查看 Windows 版本并下载更新。'),
              ),
            if (!Platform.isWindows)
              TextButton(
                onPressed: update.checking || update.downloading
                    ? null
                    : () => update.check(force: true),
                child: const Text('重新检查更新'),
              ),
            if (update.downloading) const LinearProgressIndicator(),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => update.openLink(update.downloadUrl),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                update.latest.isEmpty
                    ? '打开最新发布页下载'
                    : '浏览器直接下载 ${update.latest}',
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              update.downloadUrl,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: () => update.openLink(update.releaseUrl),
              icon: const Icon(Icons.new_releases_outlined),
              label: const Text('查看最新发布'),
            ),
            const SizedBox(height: 12),
            const Text('项目地址'),
            TextButton.icon(
              onPressed: () => update.openLink(AppUpdate.projectUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('GitHub 项目主页'),
            ),
            const SelectableText(AppUpdate.projectUrl),
          ],
        );
      },
    ),
  );
}
