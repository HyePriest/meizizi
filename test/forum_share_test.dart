import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/share_content.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/forum_header_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty descriptions use the same requested wording', () {
    for (final slogan in [null, '', '  ', '<p> </p>']) {
      expect(forumDescription({'slogan': slogan}), '吧主很懒，没有留下任何简介');
    }
    expect(forumDescription({'slogan': '  技术交流  '}), '技术交流');
  });

  test('forum links preserve the name and share as text', () async {
    final content = ShareContent.forForum('图拉丁 & 装机', {});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareContent.channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareContent.channel, null),
    );
    expect(Uri.parse(content.url).host, 'tieba.baidu.com');
    expect(Uri.parse(content.url).queryParameters['kw'], '图拉丁 & 装机');
    await content.shareLink();
    expect(calls.single.method, 'shareText');
    expect(calls.single.arguments['text'], contains(content.url));
    expect(calls.single.arguments['text'], contains('吧主很懒，没有留下任何简介'));
  });

  testWidgets('forum poster is a valid shareable PNG even without artwork', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await ShareContent.forForum('图拉丁', {
        'member_num': 8251047,
        'thread_num': 3937102,
      }).renderPoster();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 1440);
      expect(image.height, 1920);
      image.dispose();
      codec.dispose();
    });
  });

  testWidgets(
    'search precedes share, copying works, and background includes the toolbar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await LocalStore.instance.restore();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = call.arguments['text'];
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final api = TiebaApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error_code': 0,
              'forum': {'name': '图拉丁', 'avatar': 'https://example.com/a.png'},
              'thread_list': [
                {'tid': 1, 'title': '置顶', 'is_top': 1},
                {'tid': 2, 'title': '普通帖'},
              ],
              'page': {'has_more': 0},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(forum: '图拉丁', api: api),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('吧主很懒，没有留下任何简介'), findsOneWidget);
      expect(find.byTooltip('吧的更多内容'), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('吧内搜索')).dx,
        lessThan(tester.getCenter(find.byTooltip('分享吧')).dx),
      );
      expect(
        find.ancestor(
          of: find.byType(AppBar),
          matching: find.byType(ForumCover),
        ),
        findsOneWidget,
      );
      final gap =
          tester.getTopLeft(find.widgetWithText(ChoiceChip, '精华')).dy -
          tester.getBottomLeft(find.byKey(const ValueKey('pinned-1'))).dy;
      expect(gap, lessThan(24));
      await tester.tap(find.byTooltip('分享吧'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('分享吧链接'), findsOneWidget);
      expect(find.text('制作分享海报'), findsOneWidget);
      await tester.tap(find.text('复制吧链接'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(Uri.parse(copied!).queryParameters['kw'], '图拉丁');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );
}
