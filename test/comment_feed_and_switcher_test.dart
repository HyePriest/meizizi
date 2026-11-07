import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/models.dart';
import 'package:tieba/data/theme_colors.dart';
import 'package:tieba/widgets/home_thread_card.dart';
import 'package:tieba/widgets/like_button.dart';
import 'package:tieba/widgets/liquid_feed_switcher.dart';
import 'package:tieba/widgets/post_action_bar.dart';

// Shape of a recommended comment in /c/f/excellent/personalized.
final Json _commentCard = {
  'id': 2100000009257146,
  'tid': 2100000009257146,
  'title': '回复：孩子们，魔族佬真的很可爱',
  'thread_type': 81,
  'post_id': 154109196222,
  'fname': '终末地内鬼',
  'reply_num': 13,
  'agree': {'agree_num': 419, 'has_agree': 0},
  'author': {'name': '天启惩罚者', 'id': 5481625863},
  'abstract': [
    {'type': 0, 'text': ''},
  ],
  'first_post_content': [
    {'type': 0, 'text': '魔族佬来了'},
  ],
  'origin_thread_info': {'tid': '11166836274', 'title': '孩子们，魔族佬真的很可爱'},
};

void main() {
  test('a recommended comment points at its real thread and floor', () {
    final comment = feedComment(_commentCard)!;
    expect(comment.threadId, '11166836274');
    expect(comment.postId, '154109196222');
    expect(comment.threadTitle, '孩子们，魔族佬真的很可爱');
    expect(feedComment({'id': 1, 'title': '普通帖子'}), isNull);
  });

  testWidgets('comment cards show the comment and its thread', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HomeThreadCard(
              thread: _commentCard,
              user: object(_commentCard['author']),
              onOpenForum: () {},
              onOpen: () {},
              onShare: () async {},
              onBlock: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('魔族佬来了'), findsOneWidget);
    expect(find.text('回复：孩子们，魔族佬真的很可爱'), findsNothing);
    expect(find.textContaining('孩子们，魔族佬真的很可爱'), findsOneWidget);
    final like = tester.widget<LikeButton>(find.byType(LikeButton));
    expect(like.threadId, '11166836274');
    expect(like.postId, '154109196222');
    // Let the image loaders' retry timers finish.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('floor replies line up with ordinary comments', (tester) async {
    Widget bar(String floor) => CommentActionBar(
      key: ValueKey(floor),
      floor: floor,
      like: LikeButton(threadId: '1', data: const {'agree_num': 5}),
      onReply: () {},
      onShare: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Column(children: [bar('12楼'), bar('1234楼'), bar('')]),
          ),
        ),
      ),
    );
    final likes = find
        .byType(LikeButton)
        .evaluate()
        .map(
          (e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
        );
    expect(likes.toSet(), hasLength(1));
    expect(likes.first, lessThan(180));
  });

  testWidgets('the first floor keeps 转发 centered whatever the counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: ThreadActionBar(
                replyCount: 123456,
                like: LikeButton(threadId: '1', data: const {'agree_num': 1}),
                onReply: () {},
                onShare: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final share = tester.getRect(find.byTooltip('转发'));
    expect(share.center.dx, closeTo(180, .5));
  });

  testWidgets('the feed takes taps after a sideways wiggle back to start', (
    tester,
  ) async {
    var taps = 0, selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LiquidFeedSwitcher(
              selected: selected,
              onSelected: (i) => setState(() => selected = i),
              children: [
                ListView(
                  children: [
                    for (var i = 0; i < 30; i++)
                      ListTile(title: Text('item $i'), onTap: () => taps++),
                  ],
                ),
                const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('item 3')),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();
    // Back past the start: the page offset is clamped to exactly 0 again.
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('item 2'));
    expect(taps, 1);
  });

  testWidgets('a slanted downward swipe scrolls the feed', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidFeedSwitcher(
            selected: 0,
            onSelected: (_) {},
            children: [
              ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 80, child: Text('item $i')),
                ],
              ),
              const SizedBox.expand(),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(200, 400));
    // Sideways first, then mostly down: the stock recognizer took this.
    await gesture.moveBy(const Offset(-20, -12));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-6, -30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
  });

  test('status and navigation bars blend into the page', () {
    final light = immersiveOverlayStyle(Colors.white);
    expect(light.statusBarColor, Colors.transparent);
    expect(light.statusBarIconBrightness, Brightness.dark);
    final dark = immersiveOverlayStyle(Colors.black);
    expect(dark.statusBarIconBrightness, Brightness.light);
    expect(dark.systemNavigationBarColor, Colors.transparent);
    expect(
      appTheme(Colors.blue, Brightness.light).appBarTheme.systemOverlayStyle,
      isA<SystemUiOverlayStyle>(),
    );
  });
}
