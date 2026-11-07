import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_update.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/desktop_layout.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    AppUpdate.instance.check();
    // No progress events arrive while GitHub is unreachable; tick so the
    // slow-connection hint still appears.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && AppUpdate.instance.downloading) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showAppSnackBar(const AppSnackBar(content: Text('下载地址已复制')));
  }

  @override
  Widget build(BuildContext context) => DesktopFrame(
    child: Scaffold(
      appBar: AppBar(title: const Text('版本更新')),
      body: ListenableBuilder(
        listenable: AppUpdate.instance,
        builder: (context, _) {
          final update = AppUpdate.instance;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _StatusCard(update: update),
              if (update.notes.trim().isNotEmpty) ...[
                const _SectionTitle('更新内容'),
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      releaseNotesText(update.notes),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(height: 1.6),
                    ),
                  ),
                ),
              ],
              const _SectionTitle('其他下载方式'),
              _Panel(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.open_in_browser),
                      title: Text(
                        update.latest.isEmpty
                            ? '用浏览器打开发布页'
                            : '用浏览器下载 ${update.latest}',
                      ),
                      subtitle: const Text('应用内下载不了时使用'),
                      onTap: () => update.openLink(update.downloadUrl),
                      trailing: IconButton(
                        tooltip: '复制下载地址',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () => _copy(update.downloadUrl),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.new_releases_outlined),
                      title: const Text('查看发布页'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => update.openLink(update.releaseUrl),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('GitHub 项目主页'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => update.openLink(AppUpdate.projectUrl),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Text(
                  '安装包托管在 GitHub，部分网络下载较慢或无法连接。'
                  '下载在后台进行，离开此页面不会中断。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// GitHub release notes are Markdown; show them as plain readable text.
String releaseNotesText(String markdown) => markdown
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) {
      final trimmed = line.trimRight();
      final heading = RegExp(r'^#{1,6}\s+').firstMatch(trimmed);
      if (heading != null) return trimmed.substring(heading.end);
      return trimmed.replaceFirstMapped(
        RegExp(r'^(\s*)[-*+]\s+'),
        (m) => '${m[1]}• ',
      );
    })
    .join('\n')
    .replaceAll(RegExp(r'\*\*|__|`'), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.update});
  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = AppUpdate.version.isEmpty ? '读取中…' : AppUpdate.version;
    final (IconData icon, String title, Color tone) = Platform.isWindows
        ? (Icons.desktop_windows_outlined, 'Windows 桌面版', colors.primary)
        : update.readyToInstall && update.available
        ? (Icons.download_done_rounded, '新版本已下载', colors.primary)
        : update.available
        ? (Icons.system_update_rounded, '发现新版本', colors.primary)
        : update.checking
        ? (Icons.sync_rounded, '正在检查更新…', colors.onSurfaceVariant)
        : update.checkError != null
        ? (Icons.cloud_off_rounded, '暂时无法确认最新版本', colors.error)
        : update.latest.isEmpty
        ? (Icons.help_outline_rounded, '检查是否有新版本', colors.onSurfaceVariant)
        : (Icons.check_circle_rounded, '已是最新版本', colors.primary);
    final error = [
      update.checkError,
      update.error,
    ].whereType<String>().join('\n');
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tone, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        update.available
                            ? '$current  →  ${update.latest}'
                            : '当前版本 $current',
                        style: text.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Notice(text: error, color: colors.error),
            ],
            const SizedBox(height: 20),
            if (Platform.isWindows)
              FilledButton.icon(
                onPressed: () => update.openLink(update.releaseUrl),
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开发布页下载 Windows 版本'),
              )
            else if (update.downloading)
              _DownloadProgress(update: update)
            else if (update.available)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: update.install,
                icon: Icon(
                  update.readyToInstall
                      ? Icons.install_mobile_rounded
                      : Icons.download_rounded,
                ),
                label: Text(
                  update.readyToInstall
                      ? '安装 ${update.latest}'
                      : '下载 ${update.latest}',
                ),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: update.checking
                    ? null
                    : () => update.check(force: true),
                icon: update.checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(update.checking ? '正在检查…' : '重新检查'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.update});
  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fraction = update.fraction;
    final label = switch (update.stage) {
      UpdateStage.connecting => '正在连接 GitHub…',
      UpdateStage.downloading => '正在下载',
      UpdateStage.verifying => '正在校验安装包…',
    };
    final downloading = update.stage == UpdateStage.downloading;
    final muted = text.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.titleSmall)),
            if (downloading && fraction != null)
              Text(
                '${(fraction * 100).floor()}%',
                style: text.titleSmall?.copyWith(color: colors.primary),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            // Indeterminate until the size is known, and while verifying.
            value: downloading ? fraction : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                !downloading
                    ? update.stage == UpdateStage.connecting
                          ? '尚未收到数据'
                          : '即将完成'
                    : update.total > 0
                    ? '${formatBytes(update.received)} / ${formatBytes(update.total)}'
                    : '已下载 ${formatBytes(update.received)}',
                style: muted,
              ),
            ),
            if (downloading && update.speed > 0)
              Text('${formatBytes(update.speed.round())}/s', style: muted),
          ],
        ),
        if (update.stalled) ...[
          const SizedBox(height: 12),
          _Notice(
            text: update.stage == UpdateStage.connecting
                ? '连接 GitHub 较慢，当前网络可能无法访问。可以继续等待，或改用浏览器下载。'
                : '下载速度很慢或已停滞。可以继续等待，或改用浏览器下载。',
            color: colors.tertiary,
            action: TextButton(
              onPressed: () => update.openLink(update.downloadUrl),
              child: const Text('浏览器下载'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: update.cancel,
            child: const Text('取消下载'),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, this.action});
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color, height: 1.5),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
