import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/image_bytes.dart';
import 'package:tieba/widgets/hold_image_preview.dart';
import 'package:tieba/widgets/liquid_feed_switcher.dart';
import 'package:tieba/widgets/reliable_image.dart';

void main() {
  testWidgets(
    'hold waits for the full image instead of displaying cached thumbnail',
    (tester) async {
      const file = 'abcdef1234567890abcdef1234567890.jpg';
      const thumbnail = 'https://tiebapic.baidu.com/forum/wh%3D100/$file';
      const original = 'https://tiebapic.baidu.com/forum/pic/item/$file';
      ImageBytes.remember(
        thumbnail,
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
      expect(ImageBytes.preview([original]), isNotNull);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HoldImagePreview(
              urls: [original],
              child: SizedBox(height: 100, width: 100),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldImagePreview)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await gesture.up();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    },
  );

  testWidgets(
    'homepage hold does not trigger feed switching or move the list',
    (tester) async {
      final switching = <bool>[];
      final scroll = ScrollController(initialScrollOffset: 120);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiquidFeedSwitcher(
              selected: 0,
              onSelected: (_) => fail('Holding an image must not change feeds'),
              onSwitching: switching.add,
              children: [
                ListView(
                  controller: scroll,
                  children: const [
                    SizedBox(height: 200),
                    HoldImagePreview(
                      urls: [],
                      child: SizedBox(height: 100, child: Text('thumbnail')),
                    ),
                    SizedBox(height: 2000),
                  ],
                ),
                const SizedBox(),
              ],
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.byType(HoldImagePreview));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldImagePreview)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ReliableImage), findsOneWidget);
      expect(switching, isEmpty);
      expect(scroll.offset, 120);
      expect(tester.getTopLeft(find.byType(HoldImagePreview)), before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(switching, isEmpty);
      expect(scroll.offset, 120);
      expect(tester.getTopLeft(find.byType(HoldImagePreview)), before);
      expect(find.byType(ReliableImage), findsNothing);
    },
  );

  Widget page({VoidCallback? onTap}) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          GestureDetector(
            onTap: onTap,
            child: const HoldImagePreview(
              urls: [],
              child: SizedBox(height: 100, child: Text('thumbnail')),
            ),
          ),
          const SizedBox(height: 2000),
        ],
      ),
    ),
  );

  testWidgets(
    'hold shows an uncropped preview until release outside thumbnail',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(page(onTap: () => taps++));
      await tester.tap(find.text('thumbnail'));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(ReliableImage), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldImagePreview)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ReliableImage), findsOneWidget);
      expect(
        tester.widget<ReliableImage>(find.byType(ReliableImage)).fit,
        BoxFit.contain,
      );
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(find.byType(ReliableImage), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(find.byType(ReliableImage), findsNothing);
      expect(taps, 1);
    },
  );

  testWidgets('scrolling does not show a preview or block the list', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.drag(find.byType(HoldImagePreview), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.byType(ReliableImage), findsNothing);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('cancelled touch and removed thumbnail clean up the preview', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldImagePreview)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.cancel();
    await tester.pump();
    expect(find.byType(ReliableImage), findsNothing);

    final second = await tester.startGesture(
      tester.getCenter(find.byType(HoldImagePreview)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ReliableImage), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await second.up();
    await tester.pump();
    expect(find.byType(ReliableImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
