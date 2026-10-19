<div align="center">

# 贴吧

**让阅读回到帖子本身。**

一个以浏览与讨论为中心的第三方贴吧 Android 客户端。<br>
紧凑的界面、熟悉的表情，以及下次打开时仍然记得的阅读位置。

<p>
  <a href="https://github.com/HyePriest/tieba/releases/latest"><img src="https://img.shields.io/github/v/release/HyePriest/tieba?style=flat-square&amp;color=2563eb&amp;label=Release" alt="Latest release"></a>
  <a href="https://github.com/HyePriest/tieba/releases"><img src="https://img.shields.io/github/downloads/HyePriest/tieba/total?style=flat-square&amp;color=2563eb&amp;label=Downloads" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/Android-ARM64-16a34a?style=flat-square&amp;logo=android&amp;logoColor=white" alt="Android ARM64">
  <img src="https://img.shields.io/badge/Built_with-Flutter-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Built with Flutter">
</p>

<p>
  <a href="https://github.com/HyePriest/tieba/releases/latest"><img src="https://img.shields.io/badge/下载_APK-2563eb?style=for-the-badge&amp;logo=android&amp;logoColor=white" alt="下载 APK"></a>
  <a href="https://github.com/HyePriest/tieba/issues"><img src="https://img.shields.io/badge/反馈问题-18181b?style=for-the-badge&amp;logo=github&amp;logoColor=white" alt="反馈问题"></a>
</p>

[功能一览](#功能一览) · [安装与更新](#安装与更新) · [构建](#构建) · [更新记录](CHANGELOG.md)

</div>

---

## 读到哪里，就从哪里继续

从首页推荐、关注的吧或搜索进入帖子，按楼层阅读、切换热度排序，也可以只看楼主。楼中楼在评论下方预览，展开后查看完整讨论；需要回看时，直接跳转到目标楼层。

返回列表保留浏览位置，重新打开帖子恢复上次阅读的楼层与偏移。首页的「继续阅读」、浏览历史和帖子收藏，让长帖可以分几次读完。

## 熟悉的内容，清楚地呈现

正文、图片、经典贴吧表情和楼中楼使用一致的内容展示。图片支持左右翻页、双指缩放与保存原图；视频点击后加载，语音可以直接播放。

吧内等级保留数字与自定义名称，吧务身份、楼主标记与 IP 信息就近显示。白色、黑色及跟随系统三种主题，让界面适应不同的阅读环境。

## 把常用操作放在手边

点赞、文字回复、收藏与分享都在阅读页完成。回复草稿按账号和回复对象分别保存在本机，离开编辑页后仍可继续写。

「我的吧」集中展示已关注的吧，支持单吧签到与一键签到；「我的」汇集个人发帖、回帖、收藏、通知和私信。屏蔽作者、吧名或吧名关键词后，列表按自己的偏好展示内容。

## 功能一览

| 场景 | 支持内容 |
| --- | --- |
| 浏览与发现 | 首页推荐、吧与帖子搜索、最新回复／最新发布／热门／精华分类 |
| 帖子阅读 | 楼层与热度排序、只看楼主、楼中楼预览、楼层跳转、阅读位置恢复 |
| 图片与媒体 | 图片浏览与原图保存、点击播放视频、帖子及楼中楼语音播放、本地表情资源 |
| 讨论与收藏 | 文字回复、本地草稿、点赞与取消点赞、帖子收藏、系统分享、举报入口 |
| 账号与社区 | 多账号切换、关注与取消关注、单吧及一键签到、用户公开主页 |
| 消息与偏好 | 回复／点赞／@ 通知、私信记录、作者及吧屏蔽、关键词过滤、黑白主题 |

私信支持原生查看文字、图片和语音，发送入口转交官方客户端。当前暂不支持新发主题帖、回复图片上传、语音发送及完整离线阅读。部分分类、热度排序和账号操作取决于贴吧接口及登录状态。

## 安装与更新

1. 打开 [最新版本](https://github.com/HyePriest/tieba/releases/latest)，在 **Assets** 中下载名称含 `arm64` 的 `.apk` 文件。
2. 在 Android 手机上打开安装包，按系统提示允许安装。GitHub 自动生成的 Source code 压缩包用于查看源码。
3. 已安装本项目旧版时可直接覆盖更新，保留现有数据。应用内也可从「我的 → 设置 → 版本更新」检查、下载并安装新版。

当前提供 ARM64 安装包。应用包名为 `com.jknl.tieba`。

## 登录与数据

通过应用内的百度官方网页登录，亦提供 QQ 授权入口；短信、验证码及安全验证按官方页面提示完成。

- 登录凭据通过系统安全存储保存在本机，支持多个账号分别保存和切换。
- 浏览历史、阅读位置、屏蔽设置和未发送的回复草稿保存在本机。
- 贴吧请求直接连接百度服务；检查更新读取本项目的 GitHub Releases。
- 密码与验证码仅在官方登录页面输入，应用不另行保存。Android 云备份已关闭。

## 构建

使用 Flutter / Dart 与 Android SDK，依赖版本见 [pubspec.yaml](pubspec.yaml) 和 [pubspec.lock](pubspec.lock)。

```sh
flutter pub get
flutter run
```

生成 ARM64 release 安装包前，参照 [签名配置示例](android/key.properties.example) 创建本机 `android/key.properties`，并配置自己的签名证书：

```sh
flutter build apk --release --target-platform android-arm64 \
  --obfuscate --split-debug-info=build/release-symbols \
  --extra-gen-snapshot-options=--strip
```

输出位于 `build/app/outputs/flutter-apk/app-release.apk`。签名配置与证书不应提交到仓库；自行构建的不同签名版本不能直接覆盖官方 Release 安装包。

## 致谢

协议资料参考 [Tiebanana](https://github.com/Aobanana-chan/Tiebanana)、[aiotieba](https://github.com/lumina37/aiotieba) 与 TiebaLite 等社区项目，依赖与资源说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本项目是第三方客户端，与百度官方无隶属关系。贴吧商标、表情及用户内容归各自权利人所有。
