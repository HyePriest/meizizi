import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/widgets/reliable_image.dart';
import 'package:tieba/widgets/bounded_network_image.dart';

class ImageHttp extends HttpOverrides {
  final List<String> calls = [];
  final Set<String> failures;
  int closed = 0;
  ImageHttp(this.failures);
  @override
  HttpClient createHttpClient(SecurityContext? context) => ImageClient(this);
}

class ImageClient implements HttpClient {
  ImageClient(this.owner);
  final ImageHttp owner;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    owner.calls.add(uri.toString());
    if (uri.path == '/stuck-connect')
      return Completer<HttpClientRequest>().future;
    return ImageRequest(owner.failures.contains(uri.path));
  }

  @override
  set autoUncompress(bool value) {}
  @override
  void close({bool force = false}) {
    if (force) owner.closed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageRequest implements HttpClientRequest {
  ImageRequest(this.fail);
  final bool fail;
  @override
  HttpHeaders get headers => ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => ImageResponse(fail);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  ImageResponse(this.fail);
  final bool fail;
  static final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  @override
  int get statusCode => fail ? 503 : 200;
  @override
  int get contentLength => png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(png).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'stalled connection times out, closes client and permits a fresh retry',
    () async {
      final fake = ImageHttp({});
      await HttpOverrides.runZoned(() async {
        await expectLater(
          downloadImageBytes(
            'https://image.test/stuck-connect',
            idleTimeout: const Duration(milliseconds: 20),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(fake.closed, greaterThan(0));
        expect(
          await downloadImageBytes('https://image.test/recovered'),
          isNotEmpty,
        );
        expect(fake.calls.length, 2);
      }, createHttpClient: fake.createHttpClient);
    },
  );
  test(
    'HTTP failure closes client without waiting for the error body',
    () async {
      final fake = ImageHttp({'/bad'});
      await HttpOverrides.runZoned(() async {
        await expectLater(
          downloadImageBytes('https://image.test/bad'),
          throwsA(isA<NetworkImageLoadException>()),
        );
        expect(fake.closed, 1);
      }, createHttpClient: fake.createHttpClient);
    },
  );
  testWidgets(
    'image fails over once, caches success and reset cancels stale retry',
    (tester) async {
      final fake = ImageHttp({'/bad'});
      final old = HttpOverrides.current;
      HttpOverrides.global = fake;
      addTearDown(() => HttpOverrides.global = old);
      PaintingBinding.instance.imageCache.clear();
      Future<void> frame() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }

      await tester.pumpWidget(
        const MaterialApp(
          home: ReliableImage(
            urls: ['https://image.test/bad', 'https://image.test/good'],
          ),
        ),
      );
      await frame();
      await tester.pump(const Duration(milliseconds: 150));
      await frame();
      await frame();
      expect(fake.calls, ['https://image.test/bad', 'https://image.test/good']);
      await tester.pumpWidget(
        const MaterialApp(
          home: ReliableImage(urls: ['https://image.test/new']),
        ),
      );
      await frame();
      await frame();
      await tester.pump(const Duration(seconds: 7));
      expect(fake.calls.last, 'https://image.test/new');
      expect(fake.calls.length, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  test('image candidates are HTTPS, deduplicated and bounded', () {
    final sources = imageSources([
      'http://tiebapic.baidu.com/forum/pic/item/${'a' * 32}.jpg',
      'not a url',
    ]);
    expect(sources.every((s) => s.startsWith('https://')), isTrue);
    expect(sources.toSet().length, sources.length);
    expect(sources.length, lessThanOrEqualTo(5));
  });
}
