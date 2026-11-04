import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/scroll_away_header.dart';

void main() {
  for (final nested in [false, true]) {
    testWidgets(
      'toolbar follows scroll without moving content, nested=$nested',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await LocalStore.instance.restore();
        LocalStore.instance.clearReadingPages();
        final api = TiebaApi(
          client: MockClient((_) async => http.Response('{}', 200)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReadingPage(
              threadId: 'toolbar-test',
              postId: nested ? 'parent' : null,
              api: api,
              initialPage: TiebaPage({
                'forum': {'name': '测试'},
                'thread': {'id': 'toolbar-test', 'title': '滚动测试'},
                'page': {'current_page': 1, 'has_more': 0},
                nested ? 'subpost_list' : 'post_list': [
                  for (var floor = 1; floor <= 30; floor++)
                    {
                      'id': '$floor',
                      'floor': floor,
                      'author': {'id': floor, 'name_show': '作者$floor'},
                      'content': [
                        {'type': 0, 'text': '第$floor楼正文'},
                      ],
                    },
                ],
              }),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(ListView).first;
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        expect(scroll.maxScrollExtent, greaterThan(1000));
        scroll.jumpTo(350);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(list);
        final gesture = await tester.startGesture(
          Offset(viewport.left + 2, viewport.center.dy),
        );
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        double headerOffset() => tester
            .widget<ScrollAwayHeader>(find.byType(ScrollAwayHeader))
            .offset;
        final hiddenBy = scroll.pixels - 350;
        expect(hiddenBy, greaterThan(0));
        expect(hiddenBy, lessThan(48));
        expect(headerOffset(), closeTo(hiddenBy, .001));
        final anchor =
            [
              for (var floor = 1; floor <= 30; floor++)
                find.byKey(ValueKey('$floor')),
            ].firstWhere(
              (finder) =>
                  finder.evaluate().isNotEmpty &&
                  viewport.contains(tester.getCenter(finder)),
            );
        final before = tester.getTopLeft(anchor).dy;
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.getRect(list), viewport);
          expect(tester.getTopLeft(anchor).dy, closeTo(before, .1));
          expect(headerOffset(), closeTo(hiddenBy, .001));
        }

        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        expect(
          headerOffset(),
          closeTo((scroll.pixels - 350).clamp(0, 48), .001),
        );
        final showing = tester.getTopLeft(anchor).dy;
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.getRect(list), viewport);
          expect(tester.getTopLeft(anchor).dy, closeTo(showing, .1));
        }
        await gesture.moveBy(const Offset(0, -150));
        await tester.pump();
        expect(headerOffset(), 48);
        final pixelsBeforeReverse = scroll.pixels;
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        expect(
          headerOffset(),
          closeTo(48 + scroll.pixels - pixelsBeforeReverse, .001),
        );
        await gesture.up();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 31));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
