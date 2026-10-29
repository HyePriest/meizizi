import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/adaptive_feed.dart';

void main() {
  testWidgets(
    'Windows waterfall follows window width, including short windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(1280, 480);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFeedView.builder(
              itemCount: 12,
              itemBuilder: (_, index) => SizedBox(
                key: ValueKey(index),
                height: index.isEven ? 100 : 220,
                child: Text('card$index'),
              ),
            ),
          ),
        ),
      );
      Rect card(int index) => tester.getRect(find.byKey(ValueKey(index)));
      expect(find.byType(SliverCrossAxisExpanded), findsNWidgets(4));
      expect(card(0).top, card(1).top);
      expect(card(4).top, card(0).bottom);
      expect(card(5).top, card(1).bottom);
      expect(card(4).top, lessThan(card(5).top));
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      expect(find.byType(SliverCrossAxisExpanded), findsNWidgets(2));
      expect(card(2).top, card(0).bottom);
      tester.view.physicalSize = const Size(640, 600);
      await tester.pumpAndSettle();
      expect(find.byType(SliverCrossAxisGroup), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
