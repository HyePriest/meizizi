import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/theme_colors.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/pages/theme_color_page.dart';

import 'package:tieba/widgets/comment_card.dart';
import 'package:tieba/widgets/post_widgets.dart';

Json fixture({String? longText}) => {
  'thread': {'id': '99', 'title': '空间标题', 'author': {'id': 1}},
  'page': {'current_page': 1, 'has_more': 0},
  'post_list': [for (var i=1; i<=4; i++) {
    'id': '$i', 'floor': i, 'author_id': i,
    'author': {'id': i, 'name_show': '作者$i'},
    'content': [{'type': 0, 'text': i==1 && longText!=null ? longText : '正文$i'}],
  }],
};
Future<void> reset(bool mode) async {
  SharedPreferences.setMockInitialValues({'building_mode': mode});
  await LocalStore.instance.restore();
  LocalStore.instance.clearReadingPages();
}
Widget page(Json data) => MaterialApp(home: ReadingPage(threadId:'99', initialPage: TiebaPage(data),
  api: TiebaApi(client: MockClient((_) async => http.Response(jsonEncode({'error_code':0,...data}),200)))));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('building switch persists and defaults off', () async {
    await reset(false);
    expect(LocalStore.instance.buildingMode, isFalse);
    await LocalStore.instance.setBuildingMode(true);
    await LocalStore.instance.restore();
    expect(LocalStore.instance.buildingMode, isTrue);
    await LocalStore.instance.setBuildingMode(false);
  });
  for(final mode in [false,true]) {
    testWidgets('spatial order and blocked first floor in mode $mode', (tester) async {
      tester.view.physicalSize=const Size(420,1300); tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await reset(mode);
      await tester.pumpWidget(page(fixture()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first=tester.getTopLeft(find.text('正文1')).dy;
      final second=tester.getTopLeft(find.text('正文2')).dy;
      expect(mode ? first>second : first<second, isTrue);
      if(mode) {
        expect(tester.getTopLeft(find.text('空间标题')).dy, greaterThan(first));
        expect(find.text('盖楼'), findsOneWidget);
        expect(find.text('楼主层'), findsOneWidget);
      }
      await LocalStore.instance.blockUser('id:1','作者1');
      await tester.pumpAndSettle();
      expect(find.text('正文1'),findsNothing);
      expect(find.text('2楼'),findsOneWidget);
      final secondCard=tester.widget<CommentCard>(find.ancestor(of:find.text('正文2'),matching:find.byType(CommentCard)).first);
      expect(secondCard.fullWidthContent,isFalse);
      expect(find.text(mode?'全部楼层':'全部回复'),findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('long floor opens at paragraph start and returns without moving tower', (tester) async {
    await reset(true);
    final longText='开头段落\n${List.filled(100,'长正文按正常方向阅读。').join('\n')}\n结尾段落';
    await tester.pumpWidget(page(fixture(longText:longText)));
    await tester.pumpAndSettle();
    final before=tester.getTopLeft(find.text('空间标题')).dy;
    await tester.tap(find.text('从头阅读本层全文'));
    await tester.pumpAndSettle();
    expect(find.text('本层全文 · 从上向下阅读'),findsOneWidget);
    expect(find.byType(SingleChildScrollView),findsWidgets);
    await tester.tap(find.byTooltip('返回楼层'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('空间标题')).dy,closeTo(before,.5));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('blank text surrounding media does not allocate text lines', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PostContent(parts:[{'type':0,'text':'\n\n  '}]))));
    expect(find.byType(SelectionArea),findsNothing);
    expect(tester.getSize(find.byType(PostContent)).height,0);
  });
  testWidgets('exact hue input rejects invalid and applies numeric value', (tester) async {
    tester.view.physicalSize=const Size(400,900); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await reset(false);
    await tester.pumpWidget(const MaterialApp(home:ThemeColorPage()));
    await tester.ensureVisible(find.textContaining('°').first);
    await tester.tap(find.textContaining('°').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'361');
    await tester.tap(find.text('应用'));
    await tester.pump();
    expect(find.text('请输入 0–360 之间的数字'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'217.5');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('217.5°'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test('custom colors maintain readable primary and surface text', () {
    for (final bg in [Colors.white,Colors.black,const Color(0xffeecce0),const Color(0xff237654)]) {
      for(final seed in [Colors.yellow,Colors.green,Colors.purple,Colors.black]) {
        final theme=appTheme(seed,bg.computeLuminance()<=.179?Brightness.dark:Brightness.light,background:bg);
        double contrast(Color a,Color b) {final x=a.computeLuminance(),y=b.computeLuminance();return x>y?(x+.05)/(y+.05):(y+.05)/(x+.05);}
        expect(contrast(theme.colorScheme.primary,bg),greaterThanOrEqualTo(4.5));
        expect(contrast(theme.colorScheme.onSurface,bg),greaterThanOrEqualTo(4.5));
      }
    }
  });
}

