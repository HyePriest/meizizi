import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/main.dart';
import 'package:tieba/pages/home_page.dart';
import 'package:tieba/pages/theme_color_page.dart';

void main() {
  final store = LocalStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.restore();
  });

  test('system background persists and manual colors disable it', () async {
    expect(store.backgroundFollowsSystem, isFalse);
    final original = store.backgroundColor;
    await store.setBackgroundColor(original, followSystem: true);
    await store.restore();
    expect(store.backgroundFollowsSystem, isTrue);
    expect(store.resolvedBackgroundColor(Brightness.light), 0xffffffff);
    expect(store.resolvedBackgroundColor(Brightness.dark), 0xff000000);
    await store.setBackgroundColor(0xff123456);
    await store.restore();
    expect(store.backgroundFollowsSystem, isFalse);
    expect(store.resolvedBackgroundColor(Brightness.dark), 0xff123456);
  });

  testWidgets('app follows live system changes and keeps manual backgrounds', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    store.previewBackgroundColor(store.backgroundColor, followSystem: true);
    await tester.pumpWidget(const TiebaApp());
    await tester.pump();
    ThemeData theme() => Theme.of(tester.element(find.byType(HomePage)));
    expect(theme().scaffoldBackgroundColor, Colors.white);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(theme().scaffoldBackgroundColor, Colors.black);
    expect(theme().brightness, Brightness.dark);
    store.previewBackgroundColor(0xff123456);
    await tester.pump();
    expect(theme().scaffoldBackgroundColor, const Color(0xff123456));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(theme().scaffoldBackgroundColor, const Color(0xff123456));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker previews system mode, cancels and saves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final original = store.backgroundColor;
    Future<void> openPicker() async {
      await tester.pumpWidget(
        const MaterialApp(home: ThemeColorPage(background: true)),
      );
      await tester.scrollUntilVisible(find.text('根据系统切换'), 200);
    }

    Color background() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;

    await openPicker();
    expect(
      tester.getCenter(find.text('白色')).dy,
      tester.getCenter(find.text('根据系统切换')).dy,
    );
    await tester.tap(find.text('根据系统切换'));
    await tester.pump();
    expect(store.backgroundFollowsSystem, isTrue);
    expect(background(), Colors.white);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(background(), Colors.black);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(store.backgroundFollowsSystem, isFalse);
    expect(store.backgroundColor, original);

    await openPicker();
    await tester.tap(find.text('根据系统切换'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      // Preference writes run in the zone where the store was initialized.
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await store.restore();
    expect(store.backgroundFollowsSystem, isTrue);

    await tester.pumpWidget(const SizedBox());
    await openPicker();
    await tester.tap(find.text('白色'));
    await tester.pump();
    expect(store.backgroundFollowsSystem, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(store.backgroundFollowsSystem, isTrue);
    expect(tester.takeException(), isNull);
  });
}
