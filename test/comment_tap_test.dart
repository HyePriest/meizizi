import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/post_widgets.dart';

void main() {
  testWidgets(
    'comment text, line whitespace and card whitespace open exactly once; buttons stay independent',
    (tester) async {
      var opened = 0, replied = 0;
      void open() => opened++;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: InkWell(
                onTap: open,
                child: SizedBox(
                  width: 400,
                  height: 240,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PostContent(
                          parts: const [
                            {'type': 0, 'text': '普通评论'},
                          ],
                          onTextTap: open,
                        ),
                        TextButton(
                          onPressed: () => replied++,
                          child: const Text('回复'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final text = tester.getRect(find.text('普通评论'));
      await tester.tapAt(Offset(text.left + 10, text.center.dy));
      await tester.pump();
      expect(opened, 1);
      await tester.tapAt(Offset(text.right - 4, text.center.dy));
      await tester.pump();
      expect(opened, 2);
      final card = tester.getRect(find.byType(Card));
      await tester.tapAt(Offset(card.center.dx, card.bottom - 8));
      await tester.pump();
      expect(opened, 3);
      await tester.tap(find.text('回复'));
      await tester.pump();
      expect(replied, 1);
      expect(opened, 3);
      await tester.longPress(find.text('普通评论'));
      await tester.pump();
      expect(opened, 3);
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    },
  );
}
