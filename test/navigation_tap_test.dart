import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/comment_card.dart';
import 'package:tieba/widgets/home_thread_card.dart';
import 'package:tieba/widgets/liquid_feed_switcher.dart';
import 'package:tieba/widgets/thread_feed_actions.dart';

class PendingFloorApi extends TiebaApi {
  PendingFloorApi()
    : super(client: MockClient((_) async => http.Response('{}', 200)));

  var pending = Completer<TiebaPage>();
  final targets = <String?>[];

  @override
  Future<TiebaPage> floor(
    String threadId,
    String postId,
    int page, {
    String? targetReply,
  }) {
    targets.add(targetReply);
    return pending.future;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    LocalStore.instance.clearReadingPages();
  });

  testWidgets(
    'home card whitespace opens the post and controls stay separate',
    (tester) async {
      var opened = 0, forums = 0, shared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeThreadCard(
              thread: const {
                'id': '1',
                'title': '帖子正文',
                'forum_name': '测试',
                'forum_info': {'member_num': 1, 'thread_num': 2},
              },
              user: const {},
              onOpen: () => opened++,
              onOpenForum: () => forums++,
              onShare: () async => shared++,
              onBlock: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('帖子正文'));
      await tester.pump();
      expect(opened, 1);
      final actions = tester.getRect(find.byType(ThreadFeedActions));
      await tester.tapAt(
        Offset(actions.left + actions.width * .25, actions.center.dy),
      );
      await tester.pump();
      expect(opened, 2);
      await tester.tap(find.text('测试吧'));
      await tester.pump();
      expect(forums, 1);
      expect(opened, 2);
      await tester.tap(find.byTooltip('转发'));
      await tester.pump();
      expect(shared, 1);
      expect(opened, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );

  testWidgets(
    'home taps work after switching, edge swipes and cancelled swipes',
    (tester) async {
      var selected = 0, opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LiquidFeedSwitcher(
                selected: selected,
                onSelected: (value) => setState(() => selected = value),
                children: [
                  for (var i = 0; i < 2; i++)
                    InkWell(
                      onTap: () => opened++,
                      child: Center(child: Text('页面$i')),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final delta in [
        const Offset(80, 0),
        const Offset(-350, 0),
        const Offset(-80, 0),
      ]) {
        await tester.drag(find.text('页面$selected'), delta);
        await tester.pumpAndSettle();
        final before = opened;
        await tester.tap(find.text('页面$selected'));
        await tester.pumpAndSettle();
        expect(opened, before + 1);
      }
    },
  );

  testWidgets('tapping a preview opens replies before its request completes', (
    tester,
  ) async {
    final api = PendingFloorApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingPage(
          threadId: '1',
          api: api,
          initialPage: TiebaPage({
            'thread': {'id': '1', 'title': '测试帖子'},
            'page': {'current_page': 1, 'has_more': 0},
            'post_list': [
              {
                'id': '2',
                'floor': 2,
                'author': {'id': '3', 'name_show': '评论者'},
                'content': [
                  {'type': 0, 'text': '评论正文'},
                ],
                'sub_post_number': 1,
                'sub_post_list': [
                  {
                    'id': '4',
                    'author': {'id': '5', 'name_show': '回复者'},
                    'content': [
                      {'type': 0, 'text': '预览回复'},
                    ],
                  },
                ],
              },
            ],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReplyPreview));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final replies = tester
        .widgetList<ReadingPage>(find.byType(ReadingPage))
        .where((page) => page.postId == '2');
    expect(replies, hasLength(1));
    expect(replies.single.targetReplyId, '4');
    expect(api.pending.isCompleted, isFalse);
    api.pending.complete(TiebaPage({}));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('targeted reply loading is visible and retry keeps the target', (
    tester,
  ) async {
    final api = PendingFloorApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingPage(
          threadId: '1',
          postId: '2',
          targetReplyId: '4',
          api: api,
          parentPost: const {
            'id': '2',
            'content': [
              {'type': 0, 'text': '原评论'},
            ],
          },
        ),
      ),
    );
    await tester.pump();
    expect(api.targets, ['4']);
    final progress = find.byType(CircularProgressIndicator);
    expect(progress.hitTestable(), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: progress, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
    expect(find.text('原评论'), findsWidgets);
    api.pending.completeError(const TiebaException('测试网络错误'));
    await tester.pumpAndSettle();
    expect(find.text('测试网络错误'), findsOneWidget);
    api.pending = Completer<TiebaPage>();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(api.targets, ['4', '4']);
    api.pending.complete(
      TiebaPage({
        'page': {'current_page': 1, 'has_more': 0},
        'subpost_list': [
          {
            'id': '4',
            'content': [
              {'type': 0, 'text': '目标回复'},
            ],
          },
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('目标回复'), findsOneWidget);
    expect(api.targets, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
