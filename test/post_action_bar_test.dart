import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/like_button.dart';
import 'package:tieba/widgets/post_action_bar.dart';

void main() {
  for (final width in [240.0, 300.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('footer stays on one line at width $width scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: PostActionBar(
                      like: LikeButton(
                        threadId: '1',
                        data: {'agree_num': 123456},
                      ),
                      onReply: () {},
                      onFloor: () {},
                      floorCount: 12345,
                      ip: '黑龙江省哈尔滨市',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final likes = tester.getRect(find.text('123456'));
        expect(likes.width, greaterThan(20));
        expect(likes.left, greaterThanOrEqualTo(0));
        expect(likes.right, lessThanOrEqualTo(width * 5 / 16));
        expect(tester.widget<Text>(find.text('123456')).overflow, isNull);
        final reply = tester.getRect(find.text('回复'));
        final floor = tester.getRect(find.text('楼中楼 12345'));
        final ip = tester.getRect(find.text('IP：黑龙江省哈尔滨市'));
        expect(floor.center.dy, closeTo(reply.center.dy, 1));
        expect(ip.center.dy, closeTo(reply.center.dy, 1));
        expect(ip.right, lessThanOrEqualTo(width));
        expect(tester.widget<Text>(find.text('IP：黑龙江省哈尔滨市')).maxLines, 1);
      });
    }
  }
}
