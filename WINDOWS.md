# 美滋滋 Windows 桌面版

沿用 Flutter 主工程，首页、热榜和吧内列表使用与平板相同的多列瀑布流。桌面窗口宽度达到 720 时显示左侧导航；卡片按实际可用宽度与文字大小分成 2–4 列，极窄窗口恢复单列。帖子正文保持适合阅读的宽度。

## 运行

解压 Windows 压缩包，运行文件夹内的 `meizizi.exe`。请保留同目录的 DLL 和 `data` 文件夹，不能只复制 EXE。

安装版为 `meizizi-windows-<版本>-setup.exe`：双击后可选择安装位置、创建桌面快捷方式。默认仅安装到当前用户，无需管理员权限。

首次运行使用电脑上的独立账号、设置与缓存。可在“个人页”进入百度或 QQ 官方网页完成登录；Android 数据不会迁移或修改。

Windows 使用 WebView2 显示登录、官方私信、举报与视频页面。如果内置浏览器无法启动，请安装 Microsoft Edge WebView2 Runtime 后重新打开应用。

图片通过 Windows 文件窗口选择和保存，分享海报会打开保存窗口，吧简介与链接可复制到剪贴板。桌面版本更新入口打开项目发布页。

## 本地构建

- Flutter SDK、Visual Studio 的“使用 C++ 的桌面开发”工作负载，以及“C++ ATL（最新 MSVC，x86 和 x64）”组件。
- Windows 开发者模式（用于 Flutter 插件链接）。
- 运行 `tool/build-windows.ps1`；脚本只为当前进程设置 NuGet 路径，不修改系统环境变量。

输出：`build/windows/x64/runner/Release/meizizi.exe`，以及 `releases/meizizi-windows-<版本>.zip`。

已完成 Release 构建后，运行 `tool/package-windows-installer.ps1` 生成安装包。需要 Inno Setup 7 编译器和 Visual Studio 的 x64 VC++ 可再分发运行库；脚本将运行库放在应用目录内，不安装系统运行库，也不运行生成的安装包。

## 验证范围

定向布局检查覆盖不同窗口宽度下的自然高度卡片排列、列数变化，以及已有平板布局的滚动与导航行为。编译通过仅说明程序能够构建；账号登录、验证码、发帖回复、官方私信与在线音视频仍需实际交互确认。
