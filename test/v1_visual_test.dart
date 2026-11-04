import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/theme_colors.dart';
import 'package:tieba/pages/reading_page.dart';
import 'building_mode_test.dart' as fixtures;

void main() {
  for (final mode in [false,true]) {
    for(final dark in [false,true]) {
      testWidgets('reading visual mode=$mode dark=$dark', (tester) async {
        tester.view.physicalSize=const Size(400,900);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        await fixtures.reset(mode);
        final app=fixtures.page(fixtures.fixture()) as MaterialApp;
        await tester.pumpWidget(MaterialApp(theme:appTheme(Colors.deepOrange,dark?Brightness.dark:Brightness.light,background:dark?const Color(0xff151515):const Color(0xfffaf7ee)),home:app.home));
        await tester.pumpAndSettle();
        await expectLater(find.byType(ReadingPage),matchesGoldenFile('goldens/v1-${mode?'building':'normal'}-${dark?'dark':'light'}.png'));
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
      });
    }
  }
}
