import 'package:flutter/material.dart';

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
            const Text('当前版本 ${AppUpdate.version}'),
            const SizedBox(height: 16),
            Text(
              update.available
                  ? '发现新版本 ${update.latest}'
                  : update.checking
                  ? '正在检查更新…'
                  : update.error != null
                  ? '检查更新未完成'
                  : update.latest.isEmpty
                  ? '查看是否有新版本'
                  : '已是最新版本',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (update.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  update.error!,
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
            TextButton(
              onPressed: update.checking || update.downloading
                  ? null
                  : () => update.check(force: true),
              child: const Text('重新检查更新'),
            ),
            if (update.downloading) const LinearProgressIndicator(),
            if (update.available && update.notes.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('更新内容'),
              const SizedBox(height: 8),
              SelectableText(update.notes),
            ],
          ],
        );
      },
    ),
  );
}
