import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/directional_page_drag.dart';
import 'package:tieba/widgets/page_drag.dart';

void main() {
  Future<PageController> pumpPager(WidgetTester tester) async {
    final pages = PageController();
    final drag = PageDrag(pages);
    await tester.pumpWidget(
      MaterialApp(
        home: DirectionalPageDragArea(
          drag: drag,
          child: PageView(
            controller: pages,
            physics: const PageScrollPhysics(
              parent: NeverScrollableScrollPhysics(),
            ),
            children: [
              for (final name in ['热门', '精华'])
                ListView(
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 80, child: Text('$name $i')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    return pages;
  }

  testWidgets('a slanted vertical scroll stays on the current tab', (
    tester,
  ) async {
    final pages = await pumpPager(tester);
    // 40 px sideways while scrolling 160 px down: more vertical than horizontal.
    await tester.drag(find.text('热门 2'), const Offset(-40, -160));
    await tester.pumpAndSettle();
    expect(pages.page, 0);
    expect(find.text('热门 0'), findsNothing, reason: 'the list scrolled');
  });

  testWidgets('a mostly horizontal swipe switches the tab', (tester) async {
    final pages = await pumpPager(tester);
    await tester.drag(find.text('热门 2'), const Offset(-500, -30));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
  });
}
