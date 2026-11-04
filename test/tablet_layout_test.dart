import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/pages/home_page.dart';
import 'package:tieba/widgets/adaptive_feed.dart';

void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget feed({
  int count = 8,
  ScrollController? controller,
  VoidCallback? onTap,
}) => MaterialApp(
  home: Scaffold(
    body: AdaptiveFeedView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      fullWidthFirst: true,
      fullWidthLast: true,
      itemCount: count + 2,
      itemBuilder: (_, index) => SizedBox(
        key: ValueKey(index),
        height: index == 0 || index == count + 1
            ? 40
            : index.isOdd
            ? 100
            : 220,
        child: InkWell(
          onTap: onTap,
          child: Text(index == count + 1 ? 'footer' : 'item$index'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('wide feed stacks unequal cards and spans header and footer', (
    tester,
  ) async {
    viewport(tester, const Size(900, 600));
    var taps = 0;
    await tester.pumpWidget(feed(count: 4, onTap: () => taps++));
    Rect rect(int index) => tester.getRect(find.byKey(ValueKey(index)));
    expect(rect(1).top, rect(2).top);
    expect(rect(3).top, rect(1).bottom);
    expect(rect(4).top, rect(2).bottom);
    expect(rect(3).top, lessThan(rect(4).top));
    expect(rect(0).width, 876);
    expect(rect(5).width, 876);
    expect(rect(5).top, greaterThanOrEqualTo(rect(4).bottom));
    await tester.tap(find.text('item2'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long feeds stay lazy and can scroll back from the last page', (
    tester,
  ) async {
    viewport(tester, const Size(1200, 800));
    final controller = ScrollController(keepScrollOffset: false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(feed(count: 300, controller: controller));
    expect(find.byType(InkWell).evaluate().length, lessThan(50));
    controller.jumpTo(1700);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 1200);
    await tester.pumpAndSettle();
    expect(controller.offset, 1700);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(controller.offset, 1700);
    for (var i = 0; i < 6; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(find.text('footer').hitTestable(), findsOneWidget);
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('item1').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait tablets and landscape phones keep a single column', (
    tester,
  ) async {
    viewport(tester, const Size(800, 1200));
    await tester.pumpWidget(feed());
    expect(find.byType(SliverCrossAxisGroup), findsNothing);
    tester.view.physicalSize = const Size(900, 420);
    await tester.pumpAndSettle();
    expect(find.byType(SliverCrossAxisGroup), findsNothing);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byType(SliverCrossAxisGroup), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation moves left and keeps selection across rotation', (
    tester,
  ) async {
    viewport(tester, const Size(1200, 800));
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
    await tester.tap(find.text('关注的吧'));
    await tester.pump();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    tester.view.physicalSize = const Size(800, 1200);
    await tester.pump();
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNotNull,
    );
    expect(find.text('我关注的吧'), findsOneWidget);
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });
}
