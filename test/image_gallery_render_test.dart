import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/image_gallery.dart';

Future<Uint8List> png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('zoomed pan coasts, stops on touch and stays inside bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGallery(
          initialPage: 0,
          itemCount: 2,
          onPageChanged: (_) {},
          itemBuilder: (_, _) => const ColoredBox(color: Colors.red),
        ),
      ),
    );
    final viewer = find.byKey(const ValueKey('gallery-transform-0'));
    final center = tester.getCenter(viewer);
    Matrix4 matrix() => tester.widget<Transform>(viewer).transform;
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(matrix().getMaxScaleOnAxis(), closeTo(3, .001));

    await tester.flingFrom(center, const Offset(100, 40), 1000);
    final releasedX = matrix().storage[12];
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    expect(matrix().storage[12], greaterThan(releasedX));
    final touch = await tester.startGesture(center);
    await tester.pump();
    final stoppedX = matrix().storage[12];
    final stoppedY = matrix().storage[13];
    await tester.pump(const Duration(milliseconds: 100));
    expect(matrix().storage[12], stoppedX);
    expect(matrix().storage[13], stoppedY);
    await touch.up();
    await tester.pumpAndSettle();

    await tester.flingFrom(center, const Offset(180, 80), 4000);
    await tester.pumpAndSettle();
    final size = tester.getSize(viewer);
    expect(matrix().storage[12], lessThanOrEqualTo(size.width));
    expect(matrix().storage[13], lessThanOrEqualTo(size.height));
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(pages.page, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loaded images remain painted during drag and animated page settling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final images = (await tester.runAsync(
        () => Future.wait([png(Colors.red), png(Colors.blue)]),
      ))!;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundaryKey,
            child: ImageGallery(
              initialPage: 0,
              itemCount: 2,
              onPageChanged: (_) {},
              itemBuilder: (_, index) =>
                  Image.memory(images[index], fit: BoxFit.fill),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(ImageGallery));
      await tester.runAsync(
        () => Future.wait([
          for (final bytes in images)
            precacheImage(MemoryImage(bytes), context),
        ]),
      );
      await tester.pump();
      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      final drag = await tester.startGesture(const Offset(250, 400));
      await drag.moveBy(const Offset(-30, 0));
      await tester.pump();
      await drag.moveBy(const Offset(-230, 0));
      await tester.pump();
      final heldPage = pages.page!;
      expect(heldPage, greaterThan(.3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(pages.page, closeTo(heldPage, .0001));
      expect(pages.position.isScrollingNotifier.value, isTrue);

      Future<void> expectPixel(int x, Color color) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!;
        });
        final offset = (400 * 390 + x) * 4;
        expect(pixels!.getUint8(offset), (color.r * 255).round());
        expect(pixels.getUint8(offset + 1), (color.g * 255).round());
        expect(pixels.getUint8(offset + 2), (color.b * 255).round());
        expect(pixels.getUint8(offset + 3), 255);
      }

      await expectPixel(50, Colors.red);
      await expectPixel(340, Colors.blue);
      await drag.up();
      await tester.pump();
      expect(pages.page, closeTo(heldPage, .0001));
      expect(pages.position.isScrollingNotifier.value, isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      expect(pages.page, greaterThan(heldPage));
      expect(pages.page, lessThan(1));
      await expectPixel(340, Colors.blue);
      await tester.pumpAndSettle();
      expect(pages.page, closeTo(1, .0001));
      expect(pages.position.isScrollingNotifier.value, isFalse);
      await expectPixel(190, Colors.blue);
      await tester.fling(find.byType(PageView), const Offset(120, 0), 2000);
      await tester.pumpAndSettle();
      expect(pages.page, closeTo(0, .0001));
      await expectPixel(190, Colors.red);

      final shortDrag = await tester.startGesture(const Offset(250, 400));
      await shortDrag.moveBy(const Offset(-30, 0));
      await tester.pump();
      await shortDrag.moveBy(const Offset(-90, 0));
      await tester.pump(const Duration(milliseconds: 300));
      final shortPage = pages.page!;
      expect(shortPage, greaterThan(0));
      expect(shortPage, lessThan(.5));
      await shortDrag.up();
      await tester.pump();
      expect(pages.page, closeTo(shortPage, .0001));
      await tester.pump(const Duration(milliseconds: 50));
      expect(pages.page, greaterThan(0));
      expect(pages.page, lessThan(shortPage));
      await tester.pumpAndSettle();
      expect(pages.page, closeTo(0, .0001));
      await expectPixel(190, Colors.red);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('double tap zooms around the tap and can be interrupted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageGallery(
          initialPage: 0,
          itemCount: 1,
          onPageChanged: (_) {},
          itemBuilder: (_, _) => const ColoredBox(color: Colors.red),
        ),
      ),
    );
    final viewer = find.byKey(const ValueKey('gallery-transform-0'));
    final center = tester.getCenter(viewer);
    final tap = center + const Offset(70, 30);
    Matrix4 matrix() => tester.widget<Transform>(viewer).transform;
    Future<void> doubleTap() async {
      await tester.tapAt(tap);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(tap);
      await tester.pump();
    }

    await doubleTap();
    expect(matrix().getMaxScaleOnAxis(), closeTo(1, .001));
    await tester.pump(const Duration(milliseconds: 130));
    final scale = matrix().getMaxScaleOnAxis();
    expect(scale, greaterThan(1));
    expect(scale, lessThan(3));
    expect(matrix().storage[12], closeTo(-70 * (scale - 1), .01));
    expect(matrix().storage[13], closeTo(-30 * (scale - 1), .01));
    await tester.pumpAndSettle();
    expect(matrix().getMaxScaleOnAxis(), closeTo(3, .001));

    await doubleTap();
    await tester.pump(const Duration(milliseconds: 100));
    expect(matrix().getMaxScaleOnAxis(), greaterThan(1));
    expect(matrix().getMaxScaleOnAxis(), lessThan(3));
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    final interruptedScale = matrix().getMaxScaleOnAxis();
    await tester.pump(const Duration(milliseconds: 300));
    expect(matrix().getMaxScaleOnAxis(), closeTo(interruptedScale, .001));
    await drag.up();
    await tester.pumpAndSettle();
    await doubleTap();
    await tester.pumpAndSettle();
    expect(matrix().getMaxScaleOnAxis(), closeTo(1, .001));
    expect(matrix().storage[12], closeTo(0, .001));
    expect(matrix().storage[13], closeTo(0, .001));
    expect(tester.takeException(), isNull);
  });
}
