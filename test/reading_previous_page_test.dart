import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/reading/reading_controller.dart';
import 'package:tieba/pages/reading_page.dart';

TiebaPage page(int n) => TiebaPage({
  'thread': {'id': 'previous-test', 'title': '向前翻页'},
  'page': {'current_page': n, 'has_more': n < 5 ? 1 : 0},
  'post_list': [
    for (var floor = (n - 1) * 10 + 1; floor <= n * 10; floor++)
      {
        'id': '$floor',
        'floor': floor,
        'author': {'id': floor, 'name_show': '作者$floor'},
        'content': [
          {'type': 0, 'text': '第$floor楼正文'},
        ],
      },
  ],
});

class PreviousApi extends TiebaApi {
  PreviousApi()
    : super(client: MockClient((_) async => http.Response('{}', 200)));
  final requested = <int>[];
  Completer<TiebaPage>? pending;
  @override
  Future<TiebaPage> thread(
    String id,
    int n, {
    bool onlyAuthor = false,
    bool hot = false,
    bool descending = false,
    String? targetPost,
    void Function(Map<String, int>)? onFloorNumbers,
  }) async {
    requested.add(n);
    return pending == null ? page(n) : pending!.future;
  }
}

void main() {
  test(
    'previous page extends the range without losing the later-page cursor',
    () async {
      final api = PreviousApi();
      final reader = ReadingController(api);
      const query = ReadingQuery(threadId: 'previous-test');
      await reader.load(query, reset: true, initialPage: page(5));
      await reader.load(query, previous: true);
      expect(api.requested, [4]);
      expect(reader.data.firstPage, 4);
      expect(reader.data.page, 5);
      expect(reader.data.hasMore, isFalse);
      expect(reader.data.items.map((post) => number(post['floor'])), [
        for (var i = 31; i <= 50; i++) i,
      ]);
      await reader.load(query, previous: true);
      expect(api.requested, [4, 3]);
      expect(reader.data.firstPage, 3);
      expect(reader.data.page, 5);
      expect(reader.data.items.length, 30);
      reader.dispose();
      api.close();
    },
  );

  testWidgets(
    'building lower edge loads previous floors and preserves visible row',
    (tester) async {
      SharedPreferences.setMockInitialValues({'building_mode': true});
      await LocalStore.instance.restore();
      LocalStore.instance.clearReadingPages();
      final api = PreviousApi()..pending = Completer<TiebaPage>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'previous-test',
            initialPage: page(5),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看前面的楼层'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(api.requested, [4]);
      final before = tester.getTopLeft(find.text('第41楼正文')).dy;
      api.pending!.complete(page(4));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('第41楼正文')).dy, closeTo(before, 1));
      expect(find.text('查看前面的楼层'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
