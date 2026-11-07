import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/app_update.dart';
import 'package:tieba/data/platform_session.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/messages_page.dart';
import 'package:tieba/pages/update_page.dart';
import 'package:tieba/pages/user_page.dart';

class _ProfileApi extends TiebaApi {
  _ProfileApi()
    : super(client: MockClient((_) async => http.Response('', 404)));
  final requested = <bool>[];

  @override
  Future<TiebaPage> userProfile(Json user) async => TiebaPage({
    'user': {
      'id': 42,
      'name': '',
      'name_show': '昵称显示',
      'tieba_uid': '3608484434',
      'tb_age': '5.3',
      'ip_address': '江苏',
      'user_growth': {'level_id': 8},
      'fans_num': 52,
      'concern_num': 3,
      'total_agree_num': 16274,
      'my_like_num': 29,
      'thread_num': 2,
      'post_num': 715,
      'likeForum': [
        {'forum_name': '明日方舟', 'forum_id': 1},
      ],
    },
  });

  @override
  Future<TiebaPage> userPosts(
    String uid,
    int page, {
    bool replies = false,
  }) async {
    requested.add(replies);
    return TiebaPage({
      'has_more': 0,
      'post_list': [
        replies
            ? {
                'thread_id': '7',
                'post_id': '70',
                'title': '回复：原来的帖子',
                'forum_name': 'rimworld',
                'content': [
                  {
                    'post_content': [
                      {'type': 0, 'text': '这是一条回复'},
                    ],
                  },
                ],
              }
            : {
                'thread_id': '8',
                'title': '请问有防误伤模组吗',
                'forum_name': 'rimworld',
                'reply_num': '15',
                'agree': {'agree_num': '229'},
              },
      ],
    });
  }
}

void main() {
  test('release notes read as plain text', () {
    expect(
      releaseNotesText('## 1.3.0\r\n\r\n- **修复**卡住\n* 新增 `进度条`\n\n\n\n结束'),
      '1.3.0\n\n• 修复卡住\n• 新增 进度条\n\n结束',
    );
    expect(formatBytes(512), '512 B');
    expect(formatBytes(29 * 1024 * 1024 + 300 * 1024), '29.3 MB');
  });

  testWidgets('the update page shows download progress from the app', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      PlatformSession.androidChannel,
      (call) async => call.method == 'appVersion' ? '1.2.1' : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        PlatformSession.androidChannel,
        null,
      ),
    );
    final update = AppUpdate.instance;
    AppUpdate.version = '1.2.1';
    update.debugSetRelease(
      'v1.3.0',
      'https://github.com/HyePriest/meizizi/releases/download/v1.3.0/app-arm64.apk',
      notes: '- 新功能',
    );
    update.debugSetProgress(UpdateStage.connecting, 0, -1);
    await tester.pumpWidget(const MaterialApp(home: UpdatePage()));
    expect(find.text('正在连接 GitHub…'), findsOneWidget);
    expect(find.text('取消下载'), findsOneWidget);

    // The app reports bytes over the update channel.
    Future<void> progress(int received, int total) =>
        messenger.handlePlatformMessage(
          'com.jknl.tieba/update',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('progress', {
              'stage': 'downloading',
              'received': received,
              'total': total,
            }),
          ),
          (_) {},
        );
    await progress(10 * 1024 * 1024, 40 * 1024 * 1024);
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('10.0 MB / 40.0 MB'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(.25, .001));

    // Without new bytes for a while, suggest the browser.
    final start = DateTime.now();
    AppUpdate.clock = () => start.add(const Duration(seconds: 10));
    addTearDown(() => AppUpdate.clock = DateTime.now);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('改用浏览器下载'), findsOneWidget);

    update.downloading = false;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the user page shows the profile and both post lists', (
    tester,
  ) async {
    final api = _ProfileApi();
    await tester.pumpWidget(
      MaterialApp(
        home: UserPage(user: const {'id': 42}, api: api),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('昵称显示'), findsWidgets);
    expect(find.text('Lv.8'), findsOneWidget);
    expect(find.text('1.6万'), findsOneWidget);
    expect(find.text('明日方舟吧'), findsOneWidget);
    expect(find.text('请问有防误伤模组吗'), findsOneWidget);

    await tester.tap(find.text('回复 715'));
    await tester.pumpAndSettle();
    expect(api.requested, [false, true]);
    expect(find.text('这是一条回复'), findsOneWidget);
    expect(find.textContaining('原来的帖子'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  test('likes on the same post are grouped, newest first', () {
    Json like(String post, int who) => {
      'post_id': post,
      'thread_id': '9',
      'agreeer': {'id': who},
    };
    final groups = groupLikes([
      like('100', 1),
      like('200', 2),
      like('100', 3),
      like('100', 4),
      {
        'thread_id': '7',
        'agreeer': {'id': 5},
      },
    ]);
    expect(groups.map((g) => g.length), [3, 1, 1]);
    expect(groups.first.map((g) => object(g['agreeer'])['id']), [1, 3, 4]);
  });

  testWidgets('消息 puts 私信 beside replies, likes and mentions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MessagesPage(counts: {2: 5})),
    );
    await tester.pump();
    for (final tab in ['私信', '回复我的', '收到的赞', '@我的']) {
      expect(find.text(tab), findsOneWidget);
    }
    expect(find.text('5'), findsOneWidget);
    // Logged out here, so the 私信 tab asks to log in.
    expect(find.text('登录后查看私信'), findsOneWidget);
  });

  testWidgets('replies keep loading past short pages, without a button', (
    tester,
  ) async {
    final api = _PagedApi();
    await tester.pumpWidget(
      MaterialApp(
        home: UserPage(user: const {'id': 42}, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复 715'));
    await tester.pumpAndSettle();
    // Scroll to the end repeatedly; each time the next page arrives.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.text('回复 715'), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    expect(api.replyPages, [1, 2, 3, 4]);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('没有更多了'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('only a mostly sideways swipe switches 主题帖 and 回复', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserPage(user: const {'id': 42}, api: _ProfileApi()),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.getCenter(find.text('请问有防误伤模组吗'));
    // Slanted downward scroll: stays on 主题帖.
    await tester.dragFrom(list, const Offset(-120, -160));
    await tester.pumpAndSettle();
    expect(find.text('这是一条回复'), findsNothing);
    await tester.flingFrom(
      tester.getCenter(find.text('请问有防误伤模组吗')),
      const Offset(-300, 10),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.text('这是一条回复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}

/// Replies arrive in short pages (17 or 18 of 20) with no has_more, as the
/// real feed does; page 4 is empty.
class _PagedApi extends _ProfileApi {
  final replyPages = <int>[];

  @override
  Future<TiebaPage> userPosts(
    String uid,
    int page, {
    bool replies = false,
  }) async {
    if (!replies) return super.userPosts(uid, page);
    replyPages.add(page);
    return TiebaPage({
      'post_list': [
        if (page < 4)
          for (var i = 0; i < 17; i++)
            {
              'thread_id': '$page$i',
              'post_id': '$page$i',
              'title': '回复：帖子 $page-$i',
              'content': [
                {
                  'post_content': [
                    {'type': 0, 'text': '回复 $page-$i'},
                  ],
                },
              ],
            },
      ],
    });
  }
}
