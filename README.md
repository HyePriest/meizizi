<div align="center">

# 美滋滋 · meizizi

**把熟悉的讨论，读出一点新花样。**

一款以阅读和讨论为中心的 Flutter Android 客户端。  
更自在的配色、更轻快的界面，以及真的能向上「盖楼」的阅读方式。

[![Flutter](https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Platform](https://img.shields.io/badge/Android-ARM64-3DDC84?logo=android&logoColor=white)](https://github.com/HyePriest/meizizi/releases)
[![Preview](https://img.shields.io/badge/Version-1.0.0--dev.1-8A63D2)](https://github.com/HyePriest/meizizi/releases)
[![GitHub Stars](https://img.shields.io/github/stars/HyePriest/meizizi?style=flat&logo=github&label=Stars)](https://github.com/HyePriest/meizizi/stargazers)
[![GitHub Release](https://img.shields.io/github/v/release/HyePriest/meizizi?include_prereleases&label=Release)](https://github.com/HyePriest/meizizi/releases)

**[下载应用](https://github.com/HyePriest/meizizi/releases)** · **[反馈问题](https://github.com/HyePriest/meizizi/issues)** · **[更新记录](CHANGELOG.md)**

</div>

---

## 认识美滋滋

美滋滋是一款用于浏览百度贴吧内容的非官方 Android 客户端。你可以发现感兴趣的讨论、阅读帖子、参与回复，也可以决定应用的颜色和阅读方式。

新版围绕**阅读体验与交互细节**重新设计首页和帖子页面，并加入自由调色、动态效果与实验性的「盖楼模式」。

## 盖楼模式：从一楼往上盖

让「盖楼」成为真正的阅读方式：**一楼在底部，二楼、三楼依次向上堆叠**。楼层像建筑一样逐层升高，而每层内部的文字依然按正常方向阅读。

- 在「我的 → 设置 → 盖楼模式」中开启，默认关闭，随时切回常规布局。
- 长正文和多图内容可以通过正常方向的全文阅读面板查看；楼中楼详情保留常规阅读顺序。
- 屏蔽内容时，楼层以拆砖、收拢的方式退场；普通模式保留碎裂效果。

> 盖楼模式目前是实验功能，长帖滚动、位置恢复和部分动画细节仍在完善。

## 界面，也有自己的性格

**洪水式切换**  
推荐与热榜之间采用跟随手势的液体过渡效果；反向滑动时，切换进度也能自然撤回。

**自由调色**  
分别调整页面背景与强调色，不再局限于黑白两种主题。支持色相微调、数值输入与 HEX 色值，预览满意后再保存。

**经典表情图标**  
桌面图标可以按星期轮换不同的经典表情。部分启动器可能因为缓存而延迟更新。

**细节动画**  
分享操作加入弓箭动效；屏蔽内容时使用与阅读模式相匹配的反馈动画。菜单、身份标签、等级显示和帖子排版也经过统一调整。

## 日常使用

| 场景 | 支持内容 |
| --- | --- |
| 浏览与发现 | 首页推荐、贴吧热议榜、话题热门与最新讨论、分类搜索 |
| 帖子阅读 | 楼层排序、楼主筛选、楼层跳转、楼中楼、阅读位置恢复 |
| 图片与媒体 | 图片浏览、缩放与原图保存、视频播放、语音播放 |
| 参与讨论 | 文字回复、本地草稿、点赞、收藏、生成帖子分享图 |
| 账号与关注 | 官方网页登录、多账号切换、公开主页、关注的吧、签到 |
| 消息与偏好 | 回复与点赞通知、@ 消息、私信查看、作者和吧屏蔽、关键词过滤 |

首页支持搜索框随滚动方向收起或显示；「我的吧」集中展示关注的吧、最近浏览与继续阅读。

**目前的功能边界：**暂不支持新发主题帖、回复图片上传、语音发送、原生私信发送及完整离线阅读。私信可以查看文字、图片和语音，发送入口交由官方客户端处理。部分功能受登录状态、安全验证及接口可用性影响。

## 安装

1. 前往 **[Releases](https://github.com/HyePriest/meizizi/releases)**，打开最新的预览版本。
2. 在 **Assets** 中下载文件名包含 `arm64` 的 `.apk` 文件。
3. 在 ARM64 Android 设备上安装。GitHub 自动生成的 *Source code* 压缩包不是安装包。

当前主要提供 Android ARM64 安装包；预览版请以 Releases 页面为准，应用内更新不一定提示预发布版本。更新前建议保存重要草稿，若出现签名冲突，请核对安装包来源。

## 登录与数据

- 通过应用内打开的官方网页完成登录及必要的验证码、安全验证。
- 账号凭据使用系统安全存储保存在本机；密码和验证码仅在官方页面输入，应用不另行保存。
- 浏览记录、阅读位置、屏蔽设置和未发送的回复草稿保存在本机；Android 云备份已关闭。
- 内容请求连接百度相关服务，版本检查访问本项目的 GitHub Releases。

## 从源码构建

需要 Flutter / Dart、Android SDK 与 JDK。实际依赖版本请参考 [`pubspec.yaml`](pubspec.yaml) 和 [`pubspec.lock`](pubspec.lock)。

```sh
flutter pub get
flutter run
```

构建 ARM64 Release 安装包之前，请参照 [`android/key.properties.example`](android/key.properties.example) 配置本机签名证书：

```sh
flutter build apk --release --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/release-symbols \
  --extra-gen-snapshot-options=--strip
```

APK 默认输出到 `build/app/outputs/flutter-apk/app-release.apk`。不要把签名证书或签名配置提交到仓库；不同签名的安装包通常无法直接覆盖安装。

## 反馈与致谢

发现问题，可以到 **[Issues](https://github.com/HyePriest/meizizi/issues)** 反馈，附上设备型号、应用版本、复现步骤；阅读问题最好附公开帖子链接。请勿提交 Cookie、登录凭据或私人聊天记录。

协议与实现参考了 [Tiebanana](https://github.com/Aobanana-chan/Tiebanana)、[aiotieba](https://github.com/lumina37/aiotieba) 及 TiebaLite 等社区项目。第三方依赖与素材信息见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

美滋滋是非官方客户端，与百度官方不存在隶属或合作关系。贴吧商标、表情及用户内容归各自权利人所有。
