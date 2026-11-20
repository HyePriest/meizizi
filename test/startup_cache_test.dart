import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/image_bytes.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/features/home/home_controller.dart';
import 'package:tieba/pages/home_page.dart';
import 'package:tieba/pages/profile_page.dart';

http.Response _homeResponse(List<Map<String, dynamic>> threads) =>
    http.Response(
      jsonEncode({'error_code': 0, 'has_more': 1, 'thread_list': threads}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _thread(String id, String title) => {
  'id': id,
  'title': title,
  'forum_name': '测试',
  'author': {'id': 'u$id', 'name_show': '用户$id'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    HomeController.clearPreload();
    ImageBytes.resetCacheDirectory();
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
  });

  tearDown(() {
    HomeController.clearPreload();
    ImageBytes.resetCacheDirectory();
  });

  test('home feed cache seeds controller immediately and survives restore', () async {
    final api1 = TiebaApi(
      client: MockClient(
        (_) async => _homeResponse([_thread('1', '缓存帖子一')]),
      ),
    );
    final first = HomeController(api: api1);
    addTearDown(first.dispose);
    await first.load(reset: true);
    // Allow queued SharedPreferences write to finish.
    await Future<void>.delayed(Duration.zero);

    await LocalStore.instance.restore();
    expect(LocalStore.instance.hasHomeFeedCache(''), isTrue);
    expect(LocalStore.instance.homeFeedCacheBytes(), greaterThan(0));

    final api2 = TiebaApi(
      client: MockClient(
        (_) async => _homeResponse([_thread('2', '最新帖子二')]),
      ),
    );
    final second = HomeController(api: api2);
    addTearDown(second.dispose);
    // Cached post is available immediately as page 1 so launch does not auto-refresh.
    expect(second.state.items.map((e) => e['title']), ['缓存帖子一']);
    expect(second.state.page, 1);

    // Explicit pull-to-refresh (reset: true) replaces with fresh posts.
    await second.load(reset: true);
    expect(second.state.items.map((e) => e['title']), ['最新帖子二']);
    expect(second.state.page, 1);
  });

  testWidgets('opening HomePage with cache shows cached posts without auto-refreshing', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.instance.saveHomeFeedCache('', [_thread('1', '刚看到的帖子')], {}),
    );
    var calls = 0;
    final api = TiebaApi(
      client: MockClient((_) async {
        calls++;
        return _homeResponse([_thread('2', '不该自动刷出的帖子')]);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: HomePage(api: api)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('刚看到的帖子'), findsOneWidget);
    expect(find.text('不该自动刷出的帖子'), findsNothing);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  test('resolved splash preload populates frame 0 without duplicate request', () async {
    var calls = 0;
    final preloadApi = TiebaApi(
      client: MockClient((_) async {
        calls++;
        return _homeResponse([_thread('10', '开屏预加载帖子')]);
      }),
    );
    addTearDown(preloadApi.close);

    final preloaded = await HomeController.preloadHome(api: preloadApi);
    expect(preloaded, isNotNull);
    expect(calls, 1);

    var fallbackCalls = 0;
    final fallbackApi = TiebaApi(
      client: MockClient((_) async {
        fallbackCalls++;
        return _homeResponse([_thread('99', '不应触发')]);
      }),
    );
    final controller = HomeController(api: fallbackApi, usePreload: true);
    addTearDown(controller.dispose);

    expect(controller.state.page, 1);
    expect(controller.state.items.map((e) => e['title']), ['开屏预加载帖子']);
    expect(fallbackCalls, 0);
  });

  test('in-flight splash preload is reused by controller load without duplicate call', () async {
    final gate = Completer<http.Response>();
    var preloadCalls = 0;
    final preloadApi = TiebaApi(
      client: MockClient((_) {
        preloadCalls++;
        return gate.future;
      }),
    );
    addTearDown(preloadApi.close);

    unawaited(HomeController.preloadHome(api: preloadApi));

    var fallbackCalls = 0;
    final fallbackApi = TiebaApi(
      client: MockClient((_) async {
        fallbackCalls++;
        return _homeResponse([_thread('99', '不应触发')]);
      }),
    );
    final controller = HomeController(api: fallbackApi, usePreload: true);
    addTearDown(controller.dispose);

    expect(controller.state.page, 0);
    final loadFuture = controller.load(reset: true);
    gate.complete(_homeResponse([_thread('20', '复用中的预加载帖子')]));
    await loadFuture;

    expect(preloadCalls, 1);
    expect(fallbackCalls, 0);
    expect(controller.state.items.map((e) => e['title']), ['复用中的预加载帖子']);
    expect(controller.state.page, 1);
  });

  testWidgets('settings bottom clear cache wipes image and feed cache only', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('meizizi_cache_test_');
    final imagesDir = Directory('${temp.path}/images')..createSync();
    final cachedFile = File('${imagesDir.path}/sample.bin')
      ..writeAsBytesSync(Uint8List(4096));
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    ImageBytes.cacheDirectoryOverride = imagesDir.path;

    await tester.runAsync(() async {
      await LocalStore.instance.visitThread('7', '保留的历史帖子', '测试');
      await LocalStore.instance.saveHomeFeedCache('', [_thread('1', '临时首页缓存')], {});
    });

    Future<void> flushIo() async {
      for (var i = 0; i < 16; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SettingsContent())),
    );
    await flushIo();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('清理缓存'), 300);
    expect(find.text('清理缓存'), findsOneWidget);
    expect(find.textContaining('KB'), findsOneWidget);

    await tester.tap(find.text('清理缓存'));
    await tester.pumpAndSettle();
    expect(find.text('清理缓存？'), findsOneWidget);

    await tester.tap(find.text('清理'));
    await tester.pump();
    await flushIo();
    await tester.pumpAndSettle();

    expect(cachedFile.existsSync(), isFalse);
    expect(LocalStore.instance.hasHomeFeedCache(''), isFalse);
    // User browsing history must remain untouched.
    expect(LocalStore.instance.history.single['id'], '7');
    expect(find.text('暂无缓存'), findsOneWidget);
  });
}
