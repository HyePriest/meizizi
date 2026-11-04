import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/pages/image_page.dart';
import 'package:tieba/pages/reading_page.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'gallery follows a held finger, reverses, snaps and keeps zoom panning',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImagePage(
            url: 'https://example.com/1.png',
            urls: [
              'https://example.com/1.png',
              'https://example.com/2.png',
              'https://example.com/3.png',
            ],
          ),
        ),
      );
      await tester.pump();
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      final start = tester.getCenter(find.byType(PageView));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-180, 0));
      await tester.pump();
      final forward = pages.page!;
      expect(forward, greaterThan(.1)); // Still holding the pointer.
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(pages.page!, lessThan(forward));
      await gesture.moveBy(const Offset(-450, 0));
      await tester.pump();
      await gesture.up();
      await frames(tester);
      expect(pages.page, closeTo(1, .001));
      expect(find.text('2 / 3'), findsOneWidget);

      final viewer = find.byKey(const ValueKey('gallery-transform-1'));
      final center = tester.getCenter(viewer);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await frames(tester);
      final transform = tester.widget<Transform>(viewer).transform;
      expect(transform.getMaxScaleOnAxis(), closeTo(3, .01));
      final before = transform.storage[12];
      await tester.drag(viewer, const Offset(100, 0));
      await frames(tester);
      expect(pages.page, closeTo(1, .001));
      expect(
        tester.widget<Transform>(viewer).transform.storage[12],
        isNot(closeTo(before, .1)),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );

  testWidgets('gallery short fast flicks turn pages in both directions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ImagePage(
          url: 'https://example.com/1.png',
          urls: ['https://example.com/1.png', 'https://example.com/2.png'],
        ),
      ),
    );
    await tester.pump();
    final view = find.byType(PageView);
    final pages = tester.widget<PageView>(view).controller!;
    for (var i = 0; i < 3; i++) {
      await tester.fling(view, const Offset(-80, 0), 2000);
      await frames(tester);
      expect(pages.page, closeTo(1, .001));
      await tester.fling(view, const Offset(80, 0), 2000);
      await frames(tester);
      expect(pages.page, closeTo(0, .001));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('gallery settles smoothly and a new swipe interrupts settling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ImagePage(
          url: 'https://example.com/1.png',
          urls: ['https://example.com/1.png', 'https://example.com/2.png'],
        ),
      ),
    );
    await tester.pump();
    final view = find.byType(PageView);
    final pages = tester.widget<PageView>(view).controller!;
    await tester.fling(view, const Offset(-120, 0), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(pages.page, greaterThan(0));
    expect(pages.page, lessThan(1));
    expect(pages.position.isScrollingNotifier.value, isTrue);
    final before = pages.page!;
    final back = await tester.startGesture(tester.getCenter(view));
    await back.moveBy(const Offset(30, 0));
    await tester.pump();
    await back.moveBy(
      const Offset(100, 0),
      timeStamp: const Duration(milliseconds: 50),
    );
    await tester.pump();
    expect(pages.page, lessThan(before));
    await back.moveBy(
      const Offset(100, 0),
      timeStamp: const Duration(milliseconds: 80),
    );
    await back.up();
    await frames(tester);
    expect(pages.page, closeTo(0, .001));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('gallery pinch and first/last page boundaries', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ImagePage(
          url: 'https://example.com/1.png',
          urls: ['https://example.com/1.png', 'https://example.com/2.png'],
        ),
      ),
    );
    await tester.pump();
    final view = find.byType(PageView);
    final pages = tester.widget<PageView>(view).controller!;
    await tester.drag(view, const Offset(500, 0));
    await frames(tester);
    expect(pages.page, closeTo(0, .001));
    final center = tester.getCenter(view);
    final left = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await left.moveBy(const Offset(-60, 0));
    await right.moveBy(const Offset(60, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await frames(tester);
    final transform = tester
        .widget<Transform>(find.byKey(const ValueKey('gallery-transform-0')))
        .transform;
    expect(transform.getMaxScaleOnAxis(), greaterThan(1.2));
    expect(pages.page, closeTo(0, .001));
    // Return to base scale, then test the last-page boundary.
    final centerAfterPinch = tester.getCenter(view);
    await tester.tapAt(centerAfterPinch);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centerAfterPinch);
    await frames(tester);
    await tester.drag(view, const Offset(-600, 0));
    await frames(tester);
    expect(pages.page, closeTo(1, .001));
    await tester.drag(view, const Offset(-500, 0));
    await frames(tester);
    expect(pages.page, closeTo(1, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  for (final position in ['top', 'middle', 'collapsed']) {
    testWidgets(
      'forum follows finger and retains $position header through empty category and chip switching',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await LocalStore.instance.restore();
        final pending = Completer<void>();
        final api = TiebaApi(
          client: MockClient((request) async {
            if (request.bodyFields['sort_type'] == '0') await pending.future;
            return http.Response(
              jsonEncode({
                'error_code': 0,
                'forum': {'id': 1, 'name': '测试'},
                'thread_list': request.bodyFields['sort_type'] == '0'
                    ? []
                    : [
                        for (var i = 0; i < 30; i++)
                          {'tid': i + 1, 'title': '测试帖$i', 'abstract': '内容'},
                      ],
                'page': {'has_more': 0},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReadingPage(forum: '测试', api: api),
          ),
        );
        await frames(tester);
        final outer = tester
            .widget<NestedScrollView>(find.byType(NestedScrollView))
            .controller!;
        final target = position == 'top'
            ? 0.0
            : position == 'middle'
            ? outer.position.maxScrollExtent / 2
            : outer.position.maxScrollExtent;
        outer.jumpTo(target);
        await tester.pump();
        final barTop = tester
            .getTopLeft(find.widgetWithText(ChoiceChip, '热门'))
            .dy;
        ScrollPosition? retained;
        double? retainedOffset;
        if (position == 'collapsed') {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -400),
          );
          await frames(tester);
          retained = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(CustomScrollView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          retainedOffset = retained.pixels;
          expect(retainedOffset, greaterThan(0));
        }
        final pageView = find.byType(PageView);
        final pages = tester.widget<PageView>(pageView).controller!;
        final start = tester.getCenter(pageView);
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(-100, 0));
        await tester.pump();
        expect(pages.page, greaterThan(1.1));
        expect(outer.offset, closeTo(target, .01));
        expect(
          tester.getTopLeft(find.widgetWithText(ChoiceChip, '热门')).dy,
          closeTo(barTop, .01),
        );
        await gesture.moveBy(const Offset(-130, 0));
        await gesture.up();
        await frames(tester);
        expect(pages.page, closeTo(2, .001));
        expect(
          find.byType(CircularProgressIndicator).hitTestable(),
          findsOneWidget,
        );
        expect(outer.offset, closeTo(target, .01));
        pending.complete();
        await frames(tester);
        expect(find.text('当前分类暂无帖子'), findsOneWidget);
        expect(outer.offset, closeTo(target, .01));
        expect(
          tester.getTopLeft(find.widgetWithText(ChoiceChip, '热门')).dy,
          closeTo(barTop, .01),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '热门'));
        await frames(tester);
        expect(pages.page, closeTo(1, .001));
        expect(outer.offset, closeTo(target, .01));
        if (retained != null)
          expect(retained.pixels, closeTo(retainedOffset!, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 31));
      },
    );
  }
}
