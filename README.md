# 贴吧

一个简洁的 Flutter 第三方百度贴吧 Android 客户端。应用名称为「贴吧」，包名 `com.jknl.tieba`。

## 下载与安装

前往 [Releases](https://github.com/HyePriest/tieba/releases) 下载 `tieba-0.4.0-arm64-preview.apk`，在 Android 手机上打开安装。

当前安装包面向 ARM64 手机，为 **0.4.0 预览版**，使用调试签名。它不是应用商店正式发行包；后续若调整签名，会在发布说明中写明升级方式。

## 功能

- 底部「首页 / 我的吧 / 我」导航，顶部搜索吧或帖子。
- 首页帖子、所属吧独立跳转；帖子内部可以进入对应的吧。
- 我的吧、最近浏览、吧头像和单吧 / 一键签到。
- 多账号本地保存与直接切换。
- 帖子、评论、楼中楼浏览与文字回复，失败保留草稿。
- 帖子与评论点赞、取消点赞。
- 「最新回复 / 最新发布 / 热门 / 精华」分类。
- 头像、贴吧表情、完整年月日时间。
- 图片全区域缩放、拖动、双击放大与下载保存。
- 首页屏蔽吧或作者，在「我」中查看和解除屏蔽。

「最新回复」按最后回复时间排序；「最新发布」按发帖时间排序。热门分区是否有效取决于对应贴吧的服务器支持。

暂未实现：新发主题帖、回复图片上传、离线缓存。

## 隐私与账号

密码和短信验证码只输入百度官方登录网页。应用读取自身 WebView 中必要的百度登录 Cookie，并使用 Android 安全存储在手机本地加密保存多个账号；不保存密码，不将登录凭据上传到项目作者的服务器，也不输出凭据到日志。

网络请求直接通过 HTTPS 连接百度服务。最近浏览、屏蔽名单和未发送草稿保存在本机；屏蔽名单影响本机首页展示。安卓备份已关闭。

Android 10 及以上保存图片到相册 `Pictures/Tieba`；较旧系统使用系统文件保存窗口。

## 开发与构建

需要 Flutter、Android SDK 和兼容的 JDK。当前版本开发环境使用 Flutter 3.47.6 / Dart 3.13.5。

Android 构建配置：API 36、Gradle 9.6.0、NDK 28.2.13676358、CMake 3.22.1。SDK 路径由 Flutter 在本机生成的 `android/local.properties` 指定，不包含在仓库中。

```sh
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

APK 输出：`build/app/outputs/flutter-apk/app-release.apk`。

目前 `release` 构建同样使用模板调试签名；若自行正式发行，请在仓库外准备自己的签名私钥与密码并配置签名。构建缓存、私钥、账号数据和本机配置不属于公开源码。

Windows 下项目与 Pub 缓存可能位于不同磁盘，因此项目关闭了 Kotlin 增量缓存。

## 接口与第三方组件

使用百度 HTTPS 接口进行浏览、搜索、登录确认、回复、签到与点赞。协议资料参考 [Tiebanana](https://github.com/Aobanana-chan/Tiebanana) 与 [aiotieba](https://github.com/lumina37/aiotieba)。本项目独立实现界面、请求与解析，没有复制其客户端源码或素材。

这些接口不是面向第三方客户端的稳定公开 API，可能受到验证码、账号风控或接口变更影响。发送或签到结果不明确时不会自动重试，需先刷新核对。

依赖及许可信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；公开源码目前尚未指定开源许可证。

## 验证范围

0.4.0 已通过静态分析并成功构建 APK。发布过程不使用账号自动执行回复、点赞或签到；不宣称所有设备和账号均已实测。

