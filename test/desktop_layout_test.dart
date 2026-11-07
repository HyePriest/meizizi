import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/adaptive_feed.dart';
import 'package:tieba/widgets/desktop_layout.dart';
import 'package:tieba/widgets/feed_list_item.dart';
import 'package:tieba/widgets/section_tabs.dart';

import 'building_mode_test.dart' as reading;

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
final android = TargetPlatformVariant.only(TargetPlatform.android);

void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget home, {GlobalKey<NavigatorState>? navigator}) {
  final key = navigator ?? GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: key,
    builder: (_, child) =>
        DesktopNavigationInput(navigatorKey: key, child: child!),
    home: home,
  );
}

Widget framedPage(String title) => DesktopFrame(
  child: Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const SizedBox.expand(key: ValueKey('body')),
  ),
);

void main() {
  testWidgets('desktop pages sit in a centered column', (tester) async {
    viewport(tester, const Size(1600, 900));
    await tester.pumpWidget(app(framedPage('设置')));
    final body = tester.getRect(find.byKey(const ValueKey('body')));
    expect(body.width, desktopColumnWidth);
    expect(body.center.dx, 800);
  }, variant: windows);

  testWidgets('phone pages are not framed', (tester) async {
    viewport(tester, const Size(1600, 900));
    await tester.pumpWidget(app(framedPage('设置')));
    expect(tester.getRect(find.byKey(const ValueKey('body'))).width, 1600);
  }, variant: android);

  testWidgets('wide desktop feeds keep a maximum width', (tester) async {
    viewport(tester, const Size(2000, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveFeedView.builder(
            itemCount: 8,
            itemBuilder: (_, i) => SizedBox(key: ValueKey(i), height: 120),
          ),
        ),
      ),
    );
    final first = tester.getRect(find.byKey(const ValueKey(0)));
    final fourth = tester.getRect(find.byKey(const ValueKey(3)));
    expect(first.left, (2000 - desktopFeedWidth) / 2);
    expect(fourth.right, 2000 - (2000 - desktopFeedWidth) / 2);
    expect(tester.takeException(), isNull);
  }, variant: windows);

  testWidgets('feed tabs stay together on desktop', (tester) async {
    viewport(tester, const Size(1600, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTabs(
            labels: const ['推荐', '热榜'],
            selected: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    final gap =
        tester.getCenter(find.text('热榜')).dx -
        tester.getCenter(find.text('推荐')).dx;
    expect(gap, lessThan(200));
  }, variant: windows);

  testWidgets('desktop cards show the block button only on hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeedListItem(
            child: SizedBox(
              height: 100,
              child: Align(
                alignment: Alignment.topRight,
                child: ShowOnHover(child: Icon(Icons.close)),
              ),
            ),
          ),
        ),
      ),
    );
    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(FeedListItem)));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  }, variant: windows);

  testWidgets('Esc and the mouse back button go back a page', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(const Text('home'), navigator: navigator));
    Future<void> open() async {
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: TextField()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // In a text box the first Esc only leaves the box.
    await open();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await open();
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await mouse.down(const Offset(10, 10));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  }, variant: windows);

  testWidgets('Esc leaves a dialog that must be answered open', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(const Text('home'), navigator: navigator));
    showDialog<void>(
      context: navigator.currentContext!,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Text('确认')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('确认'), findsOneWidget);
  }, variant: windows);

  testWidgets('F5 refreshes only the page on top', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var below = 0, top = 0;
    await tester.pumpWidget(
      app(
        DesktopRefreshShortcut(
          onRefresh: () => below++,
          child: const Text('home'),
        ),
        navigator: navigator,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(below, 1);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopRefreshShortcut(
          onRefresh: () => top++,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The page does not take focus from its search box.
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>(),
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect((below, top), (1, 1));
  }, variant: windows);

  testWidgets('desktop thread page: refresh button and compact reply', (
    tester,
  ) async {
    viewport(tester, const Size(1800, 900));
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    await tester.pumpWidget(reading.page(reading.fixture()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('刷新（F5）'), findsOneWidget);
    final reply = tester.getRect(
      find.ancestor(of: find.text('写回复'), matching: find.byType(FilledButton)),
    );
    expect(reply.width, lessThan(400));
    expect(reply.center.dx, 900);
    expect(tester.takeException(), isNull);
  }, variant: windows);

  testWidgets('phone thread page is unchanged', (tester) async {
    viewport(tester, const Size(420, 900));
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    await tester.pumpWidget(reading.page(reading.fixture()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('刷新（F5）'), findsNothing);
    final reply = tester.getRect(
      find.ancestor(of: find.text('写回复'), matching: find.byType(FilledButton)),
    );
    expect(reply.width, 420 - 32);
    expect(find.byType(ReadingPage), findsOneWidget);
  }, variant: android);
}
