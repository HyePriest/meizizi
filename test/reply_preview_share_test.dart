import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/post_protocol.dart';
import 'package:tieba/data/share_content.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/comment_card.dart';
import 'package:tieba/widgets/like_button.dart';
import 'package:tieba/widgets/post_widgets.dart';

List<int> vint(int n) => [
  if (n >= 128) (n & 127) | 128,
  if (n >= 128) ...vint(n >> 7) else n,
];
List<int> integer(int f, int v) => [...vint(f * 8), ...vint(v)];
List<int> msg(int f, List<int> v) => [
  ...vint(f * 8 + 2),
  ...vint(v.length),
  ...v,
];
List<int> str(int f, String s) => msg(f, utf8.encode(s));
List<int> content(String s) => [...integer(1, 0), ...str(2, s)];
Json reply(int id, int likes) => {
  'id': id,
  'agree': {'agree_num': likes},
  'author': {'name_show': '作者$id'},
  'content': [
    {'type': 0, 'text': '回复$id'},
  ],
};
Widget page(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selects four highest likes with stable tie order', () {
    final posts = [
      reply(1, 2),
      reply(2, 9),
      reply(3, 3),
      reply(4, 9),
      reply(5, 20),
      reply(6, 0),
    ];
    expect(
      previewReplies({
        'sub_post_list': {'sub_post_list': posts},
      }).map((p) => p['id']),
      [5, 2, 4, 3],
    );
    expect(posts.first['id'], 1);
  });
  test('preserves server ranking when counters are omitted', () {
    final posts = [
      for (final id in [5, 2, 4, 3, 1]) {'id': id},
    ];
    expect(previewReplies({'sub_post_list': posts}).map((p) => p['id']), [
      5,
      2,
      4,
      3,
    ]);
  });
  test('decodes embedded replies from protobuf hot posts', () {
    final sub = [
      ...integer(1, 88),
      ...msg(2, content('热门回复')),
      ...msg(9, integer(1, 999)),
    ];
    final post = [...integer(1, 77), ...msg(15, msg(2, sub))];
    final response = decodePostResponse(
      Uint8List.fromList(msg(2, msg(6, post))),
    );
    final replies = previewReplies(
      objects(object(response['data'])['post_list']).single,
    );
    expect(replies.single['id'], 88);
    expect(object(replies.single['agree'])['agree_num'], 999);
    expect(contentSummary(replies.single['content']), '热门回复');
  });
  test('normal page requests four ranked previews', () async {
    final api = TiebaApi(
      client: MockClient((req) async {
        expect(req.bodyFields['with_floor'], '1');
        expect(req.bodyFields['floor_rn'], '4');
        expect(req.bodyFields['floor_sort_type'], '1');
        return http.Response('{"error_code":0,"post_list":[]}', 200);
      }),
    );
    await api.thread('9', 1);
    api.close();
  });
  test('share contains official permalink and readable excerpt', () async {
    final share = ShareContent.post(
      threadId: '123',
      title: '主题',
      forum: '汪峰在',
      postId: '456',
      comment: {
        'author': {'name_show': '作者'},
        'content': [
          {'type': 0, 'text': ' : 正文'},
          {'type': 3},
          {'type': 52, 'text': 'decoration'},
        ],
      },
    );
    expect(share.url, 'https://tieba.baidu.com/p/123?pid=456#456');
    expect(share.text, '主题\n汪峰在吧\n作者：正文[图片]\n${share.url}');
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareContent.channel, (value) async {
          call = value;
          return null;
        });
    await share.share();
    expect(call?.method, 'shareImage');
    expect(call?.arguments['title'], '主题');
    expect(call?.arguments['url'], share.url);
    expect(call?.arguments['bytes'], isNotEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareContent.channel, null);
  });
  testWidgets(
    'preview box opens once and count only appears for more replies',
    (tester) async {
      var opened = 0;
      final replies = [for (var i = 1; i <= 4; i++) reply(i, i)];
      await tester.pumpWidget(
        page(
          ReplyPreview(
            replies: replies,
            total: 29,
            users: const {},
            onTap: () => opened++,
          ),
        ),
      );
      expect(find.text('查看全部 29 条回复 ›'), findsOneWidget);
      await tester.tap(find.textContaining('回复2'));
      await tester.pump();
      expect(opened, 1);
      await tester.tap(find.text('查看全部 29 条回复 ›'));
      await tester.pump();
      expect(opened, 2);
      await tester.pumpWidget(
        page(
          ReplyPreview(
            replies: replies,
            total: 4,
            users: const {},
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('查看全部'), findsNothing);
    },
  );
  for (final width in [240.0, 320.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'comment layout at $width scale $scale retains likes and actions',
        (tester) async {
          var opened = 0, shared = 0, replied = 0;
          void open() => opened++;
          await tester.pumpWidget(
            page(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: width,
                  child: CommentCard(
                    user: const {'name_show': '一个很长很长的作者名称', 'level_id': 18},
                    levelNames: const {18: '本吧自定义等级'},
                    subtitle: '7楼 · 10-05 14:17',
                    ip: '黑龙江省哈尔滨市',
                    like: const LikeButton(
                      threadId: '1',
                      data: {'agree_num': 123456},
                    ),
                    onBlock: () {},
                    content: PostContent(
                      parts: const [
                        {'type': 0, 'text': '原评论正文'},
                      ],
                      onTextTap: open,
                    ),
                    actions: TextButton(
                      onPressed: () => replied++,
                      child: const Text('回复'),
                    ),
                    onShare: () => shared++,
                    onReport: () {},
                    onTap: open,
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('回复'), findsOneWidget);
          expect(find.text('本吧自定义等级'), findsOneWidget);
          expect(find.text('黑龙江省哈尔滨市'), findsOneWidget);
          await tester.tap(find.text('原评论正文'));
          await tester.pump();
          expect(opened, 1);
          await tester.tap(find.text('回复'));
          await tester.pump();
          expect(replied, 1);
          expect(opened, 1);
          await tester.tap(find.byTooltip('评论选项'));
          await tester.pumpAndSettle();
          expect(find.text('分享评论'), findsNothing);
          expect(find.text('举报评论'), findsOneWidget);
          expect(shared, 0);
          expect(opened, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'floor shows fetched parent above full replies and retains seeded metadata',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.instance.restore();
      final parent = [
        ...integer(1, 77),
        ...integer(3, 7),
        ...msg(5, content('服务端原评论')),
      ];
      final sub = [
        ...integer(1, 88),
        ...msg(2, content(' : 完整楼中楼回复')),
        ...msg(7, [...integer(2, 88), ...str(4, '回复作者'), ...integer(23, 6)]),
      ];
      final data = [
        ...msg(1, integer(6, 0)),
        ...msg(3, parent),
        ...msg(4, sub),
        ...msg(5, str(3, '帖子标题')),
      ];
      final api = TiebaApi(
        client: MockClient(
          (req) async => http.Response.bytes(msg(2, data), 200),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: '9',
            postId: '77',
            title: '帖子标题',
            api: api,
            levelNames: const {6: '天地元婴'},
            parentPost: const {
              'id': 77,
              'floor': 7,
              'author': {'name_show': '原作者'},
              'agree_num': 1217,
              'content': [
                {'type': 0, 'text': '初始原评论'},
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原评论'), findsOneWidget);
      expect(find.text('原作者'), findsOneWidget);
      expect(find.text('天地元婴'), findsOneWidget);
      expect(find.text('服务端原评论'), findsOneWidget);
      expect(find.text('初始原评论'), findsNothing);
      expect(find.text('1217'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('服务端原评论')).dy,
        lessThan(tester.getTopLeft(find.text('全部回复')).dy),
      );
      expect(
        tester.getTopLeft(find.text('全部回复')).dy,
        lessThan(tester.getTopLeft(find.text('完整楼中楼回复')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('评论选项').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('拉黑此人'));
      await tester.pumpAndSettle();
      expect(find.text('完整楼中楼回复'), findsNothing);
      expect(find.text('服务端原评论'), findsOneWidget);
      expect(LocalStore.instance.blockedUsers['id:88'], '回复作者');
      await LocalStore.instance.unblock('id:88', forum: false);
      await tester.pumpAndSettle();
      expect(find.text('完整楼中楼回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
