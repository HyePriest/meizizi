import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/reading/reading_entry.dart';
import 'package:tieba/features/reading/reading_viewport.dart';
import 'package:tieba/pages/reading_page.dart';
import 'package:tieba/widgets/comment_card.dart';

class EntryApi extends TiebaApi {
  EntryApi() : super(client: MockClient((_) async => http.Response('{}', 200)));
  var response = Completer<TiebaPage>();
  int requests = 0;
  String? requestedTarget;
  final floorResponse = Completer<TiebaPage>();

  @override
  Future<TiebaPage> threadAtFloor(String tid, int floor) =>
      floorResponse.future;

  @override
  Future<TiebaPage> thread(
    String id,
    int page, {
    bool onlyAuthor = false,
    bool hot = false,
    bool descending = false,
    String? targetPost,
    void Function(Map<String, int>)? onFloorNumbers,
  }) {
    requests++;
    requestedTarget = targetPost;
    return response.future;
  }
}

Json fixture() => {
  'thread': {'id': 'entry-test', 'title': '定位测试'},
  'page': {'current_page': 1, 'has_more': 0},
  'post_list': [
    for (var i = 1; i <= 24; i++)
      {
        'id': '$i',
        'floor': i,
        'author': {'id': i, 'name_show': '作者$i'},
        'content': [
          {'type': 0, 'text': '第$i楼正文'},
        ],
      },
  ],
};

Future<void> reset({bool building = false, Json? saved}) async {
  SharedPreferences.setMockInitialValues({
    'building_mode': building,
    if (saved != null) 'reading_positions': jsonEncode({'entry-test:': saved}),
  });
  await LocalStore.instance.restore();
  LocalStore.instance.clearReadingPages();
}

double opacity(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(Opacity),
      ),
    )
    .first
    .opacity;

ScrollPosition position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ReadingPage),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  test('idle gestures do not notify the reading page', () {
    final viewport = ReadingViewport();
    var changes = 0;
    viewport.addListener(() => changes++);
    viewport.cancel();
    viewport.cancel();
    expect(changes, 0);
    final token = viewport.begin(hideContent: true);
    viewport.cancel();
    expect(changes, 2);
    expect(viewport.hidden, isFalse);
    expect(viewport.isCurrent(token), isFalse);
    viewport.cancel();
    expect(changes, 2);
    viewport.dispose();
  });

  for (final building in [false, true]) {
    testWidgets('targeted replies remain lazy with building=$building', (
      tester,
    ) async {
      await reset(building: building);
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            postId: 'parent',
            targetReplyId: '50',
            api: EntryApi(),
            initialPage: TiebaPage({
              'thread': {'id': 'entry-test', 'title': '回复测试'},
              'page': {'current_page': 1, 'has_more': 0},
              'subpost_list': [
                for (var i = 1; i <= 100; i++)
                  {
                    'id': '$i',
                    'author': {'id': i, 'name_show': '用户$i'},
                    'content': [
                      {'type': 0, 'text': '回复正文$i'},
                    ],
                  },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      expect(find.text('回复正文50'), findsOneWidget);
      expect(tester.widgetList(find.byType(CommentCard)).length, lessThan(25));
      final before = position(tester).pixels;
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, greaterThan(before));
      expect(tester.widgetList(find.byType(CommentCard)).length, lessThan(25));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      // The IP label's shared API client closes after its idle grace period.
      await tester.pump(const Duration(seconds: 31));
    });
  }

  test('explicit targets override cache and saved sorting and offset', () {
    final entry = ReadingEntry.resolve(
      building: false,
      nested: false,
      targetPost: '40',
      cache: {'building': false, 'hot': true},
      position: {'post': '12', 'delta': 80, 'descending': true},
    );
    expect(entry.cache, isNull);
    expect(entry.target, '40');
    expect(entry.delta, 0);
    expect(entry.hot || entry.descending || entry.onlyAuthor, isFalse);
  });

  test(
    'compatible cache wins; incompatible mode starts without old location',
    () {
      final cache = <String, dynamic>{'building': true, 'offset': 500};
      expect(
        ReadingEntry.resolve(building: true, nested: false, cache: cache).cache,
        same(cache),
      );
      final entry = ReadingEntry.resolve(
        building: false,
        nested: false,
        cache: cache,
        position: {'building': true, 'post': '8', 'hot': true, 'page': 3},
      );
      expect(entry.target, isNull);
      expect(entry.page, isNull);
      expect(entry.hot, isFalse);
    },
  );

  test('saved thread and nested reply select the proper target', () {
    final saved = <String, dynamic>{
      'post': '8',
      'delta': 22,
      'hot': true,
      'descending': true,
      'only_author': true,
      'page': 3,
    };
    final thread = ReadingEntry.resolve(
      building: false,
      nested: false,
      position: saved,
    );
    expect(thread.post, '8');
    expect(thread.reply, isNull);
    expect(thread.page, 3);
    expect(thread.hot, isTrue);
    expect(thread.descending, isFalse);
    expect(thread.delta, 22);
    final nested = ReadingEntry.resolve(
      building: false,
      nested: true,
      position: saved,
    );
    expect(nested.reply, '8');
    expect(nested.post, isNull);
    expect(nested.hot || nested.descending, isFalse);
  });

  test('old completion cannot reveal a new entry; cancellation reveals immediately', () {
    final viewport = ReadingViewport();
    final old = viewport.begin(hideContent: true);
    final current = viewport.begin(hideContent: true);
    viewport.finish(old);
    expect(viewport.hidden, isTrue);
    expect(viewport.isCurrent(current), isTrue);
    viewport.cancel();
    expect(viewport.hidden, isFalse);
    expect(viewport.restoring, isFalse);
    expect(viewport.isCurrent(current), isFalse);
    viewport.finish(current);
    viewport.dispose();
  });

  testWidgets('cancel between layout frames stops lazy traversal', (
    tester,
  ) async {
    final viewport = ReadingViewport();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: scroll,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 100, child: Text('$i')),
        ),
      ),
    );
    final token = viewport.begin();
    final locating = viewport.locate(
      token: token,
      scroll: scroll,
      id: 'missing',
      valid: () => true,
      building: false,
      firstFloor: false,
      nested: false,
    );
    await tester.pump();
    viewport.cancel();
    final offset = scroll.offset;
    await tester.pump();
    expect(await locating, PlacementResult.cancelled);
    expect(scroll.offset, offset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    scroll.dispose();
    viewport.dispose();
  });

  testWidgets('failed entry load reveals retry controls', (tester) async {
    await reset();
    final api = EntryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingPage(threadId: 'entry-test', targetPostId: '20', api: api),
      ),
    );
    expect(opacity(tester), 0);
    api.response.completeError(StateError('test failure'));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(find.text('重试'), findsOneWidget);
    api.response = Completer<TiebaPage>();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(opacity(tester), 0);
    expect(api.requestedTarget, '20');
    api.response.complete(TiebaPage(fixture()));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(position(tester).pixels, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'user drag during loading cancels subsequent target positioning',
    (tester) async {
      await reset();
      final api = EntryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            targetPostId: '20',
            api: api,
          ),
        ),
      );
      final list = find.byType(ListView).first;
      ScrollStartNotification(
        metrics: position(tester),
        context: tester.element(list),
        dragDetails: DragStartDetails(),
      ).dispatch(tester.element(list));
      await tester.pump();
      expect(opacity(tester), 1);
      api.response.complete(TiebaPage(fixture()));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final target in ['20', 'missing']) {
    testWidgets('entry finishes and reveals content for target $target', (
      tester,
    ) async {
      await reset();
      final api = EntryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            targetPostId: target,
            api: api,
            initialPage: TiebaPage(fixture()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      if (target == '20') {
        expect(position(tester).pixels, greaterThan(0));
        expect(find.text('第20楼正文'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('20'))).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('cached entry restores offset without requesting the thread', (
    tester,
  ) async {
    await reset();
    final data = fixture();
    LocalStore.instance.rememberReadingPage(
      AuthStore.instance.activeId,
      'entry-test',
      {
        'items': data['post_list'],
        'data': data,
        'thread': data['thread'],
        'levels': <int, String>{},
        'offset': 400.0,
        'building': false,
        'page': 1,
        'first_page': 1,
        'more': false,
      },
    );
    final api = EntryApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingPage(threadId: 'entry-test', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(position(tester).pixels, closeTo(400, .5));
    expect(api.requests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'building entry restores saved target and first-floor entry stays at zero',
    (tester) async {
      await reset(
        building: true,
        saved: {'post': '20', 'building': true, 'delta': 0},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            initialPage: TiebaPage(fixture()),
            api: EntryApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      expect(position(tester).pixels, greaterThan(0));
      expect(find.text('第20楼正文'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            targetPostId: '1',
            initialPage: TiebaPage(fixture()),
            api: EntryApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opacity(tester), 1);
      expect(position(tester).pixels, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'explicit floor jump uses its original placement through loading',
    (tester) async {
      await reset();
      final api = EntryApi();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingPage(
            threadId: 'entry-test',
            initialPage: TiebaPage(fixture()),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('楼层跳转'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳转楼层'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '20');
      await tester.tap(find.text('跳转'));
      await tester.pump(const Duration(milliseconds: 350));
      api.floorResponse.complete(TiebaPage(fixture()));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, greaterThan(0));
      expect(find.text('第20楼正文'), findsOneWidget);
      expect(opacity(tester), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
