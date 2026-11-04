import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/post_protocol.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/widgets/poll_card.dart';
import 'package:tieba/widgets/post_widgets.dart';
import 'package:tieba/widgets/thread_thumbnails.dart';

Json poll({bool multi = false}) => {
  'title': '哪个能力更强？',
  'end_time': -1,
  'is_polled': 0,
  'is_multi': multi ? 1 : 0,
  'total_poll': 3867,
  'total_num': 3867,
  'options': [
    {'id': 1, 'num': 1832, 'text': '无下限'},
    {'id': 2, 'num': 2035, 'text': '时停15秒'},
  ],
};

Widget page(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('badge color changes at 4 and 10, while zero stays hidden', (
    tester,
  ) async {
    final colors = <int, Color>{};
    for (final level in [0, 1, 3, 4, 9, 10, 18]) {
      await tester.pumpWidget(page(ForumLevelBadge(user: {'level_id': level})));
      if (level == 0) {
        expect(find.byType(Container), findsNothing);
        continue;
      }
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).last);
      colors[level] = (box.decoration as BoxDecoration).color!;
    }
    expect(colors[1], colors[3]);
    expect(colors[4], colors[9]);
    expect(colors[10], colors[18]);
    expect(colors[1], isNot(colors[4]));
    expect(colors[4], isNot(colors[10]));
  });

  testWidgets('video uses one real cover in content and in thread lists', (
    tester,
  ) async {
    const info = {
      'video_url': 'https://example.com/video.mp4',
      'thumbnail_url': 'https://example.com/cover.jpg',
      'video_duration': 189,
    };
    await tester.pumpWidget(
      page(
        const PostContent(
          parts: [
            {'type': 5, 'text': 'https://example.com/video.mp4'},
          ],
          videoInfo: info,
        ),
      ),
    );
    expect(find.byType(VideoPreview), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
      info['thumbnail_url'],
    );
    expect(find.text('播放视频'), findsNothing);
    expect(find.text('3:09'), findsOneWidget);
    await tester.pumpWidget(
      page(const ThreadThumbnails(thread: {'id': 9, 'video_info': info})),
    );
    expect(find.byType(VideoPreview), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
      info['thumbnail_url'],
    );
  });

  testWidgets('bubble theme is omitted and comment text remains', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        const PostContent(
          parts: [
            {
              'type': 52,
              'theme_color': {
                'day': {'pattern_image': 'https://example.com/theme.png'},
              },
            },
            {'type': 0, 'text': '无下限更好用'},
          ],
        ),
      ),
    );
    expect(find.text('无下限更好用'), findsOneWidget);
    expect(find.textContaining('暂不支持'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  for (final multi in [false, true]) {
    testWidgets(
      '${multi ? 'multi' : 'single'} vote sends chosen ids once and confirms',
      (tester) async {
        final pending = Completer<bool>();
        var calls = 0;
        List<int>? selected;
        await tester.pumpWidget(
          page(
            PollCard(
              poll: poll(multi: multi),
              onRefresh: () {},
              onVote: (ids) {
                calls++;
                selected = ids;
                return pending.future;
              },
            ),
          ),
        );
        await tester.tap(find.text('无下限'));
        await tester.pump();
        await tester.tap(find.text('时停15秒'));
        await tester.pump();
        await tester.tap(find.text('提交投票'));
        await tester.pump();
        expect(selected, multi ? [1, 2] : [2]);
        expect(calls, 1);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('已投票'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      },
    );
  }

  testWidgets('polled, expired, and uncertain votes cannot submit again', (
    tester,
  ) async {
    for (final data in [
      {...poll(), 'is_polled': 1, 'polled_value': '2'},
      {...poll(), 'end_time': 1000000},
    ]) {
      await tester.pumpWidget(
        page(
          PollCard(
            key: UniqueKey(),
            poll: data,
            onRefresh: () {},
            onVote: (_) async => throw StateError('must not submit'),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    }
    var calls = 0;
    await tester.pumpWidget(
      page(
        PollCard(
          key: UniqueKey(),
          poll: poll(),
          onRefresh: () {},
          onVote: (_) async {
            calls++;
            throw const TiebaException('投票结果未确认', uncertain: true);
          },
        ),
      ),
    );
    await tester.tap(find.text('无下限'));
    await tester.pump();
    await tester.tap(find.text('提交投票'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('投票结果未确认'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  test('vote request uses the actual thread, forum and one-based ids; responses must confirm', () async {
    FlutterSecureStorage.setMockInitialValues({
      'baidu_accounts': jsonEncode({
        'active': 'tester',
        'accounts': [
          {
            'id': 'tester',
            'cookies': {'BDUSS': 'fake-test-cookie'},
          },
        ],
      }),
    });
    await AuthStore.instance.restore();
    var calls = 0;
    final api = TiebaApi(
      client: MockClient((request) async {
        calls++;
        expect(request.url.path, '/c/c/post/addPollPost');
        expect(request.url.queryParameters['cmd'], '309006');
        expect(request.headers['x_bd_data_type'], 'protobuf');
        expect(request.bodyBytes, containsAllInOrder(utf8.encode('1,2')));
        return http.Response.bytes([10, 0], 200);
      }),
    );
    try {
      await api.vote('11079059118', '123', [1, 2]);
      expect(calls, 1);
    } finally {
      api.close();
    }
    for (final body in [<int>[], utf8.encode('<html>login</html>')]) {
      final invalidApi = TiebaApi(
        client: MockClient((_) async => http.Response.bytes(body, 200)),
      );
      try {
        await expectLater(
          invalidApi.vote('11079059118', '123', [1]),
          throwsA(
            isA<TiebaException>().having((e) => e.uncertain, 'uncertain', true),
          ),
        );
      } finally {
        invalidApi.close();
      }
    }
    expect(
      decodePollResponse(
        Uint8List.fromList([10, 4, 8, 5, 18, 0]),
      )['error']['errorno'],
      5,
    );
  });
}
