import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/post_protocol.dart';
import 'package:tieba/data/models.dart';
import 'package:tieba/pages/profile_page.dart';
import 'package:tieba/widgets/post_widgets.dart';

void main() {
  test('hehe uses the available numbered resource for codes and old URLs', () {
    for (final part in [
      {'text': 'image_emoticon'},
      {'text': 'image_emoticon1'},
      {
        'src': 'https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon.png',
      },
    ]) {
      expect(emojiUrl(part), endsWith('/image_emoticon1.png'));
    }
    expect(
      emojiUrl({'text': 'image_emoticon25'}),
      endsWith('/image_emoticon25.png'),
    );
  });
  test(
    'floor protobuf retains structured images instead of HTML summaries',
    () {
      List<int> field(int id, List<int> data) => [
        (id << 3) | 2,
        data.length,
        ...data,
      ];
      final image = [
        8,
        3,
        ...field(4, 'https://example.com/image.jpg'.codeUnits),
      ];
      final reply = [8, 7, ...field(2, image)];
      final body = Uint8List.fromList(field(2, field(4, reply)));
      final result = decodeFloorResponse(body);
      final parts = contentParts(
        objects(object(result['data'])['subpost_list']).single['content'],
      );
      expect(parts.single['type'], 3);
      expect(parts.single['src'], 'https://example.com/image.jpg');
    },
  );
  testWidgets('type 20 floor image with only CDN URL renders as an image', (
    tester,
  ) async {
    const url = 'https://example.com/floor.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostContent(
            parts: [
              {'type': 20, 'text': '[图片]', 'cdn_src': url},
            ],
          ),
        ),
      ),
    );
    expect(find.text('[图片]'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, url);
  });
  test('image addresses skip empty and non-URL placeholder fields', () {
    expect(
      postImageUrl({'cdn_src': '[图片]', 'big_cdn_src': '//example.com/a.jpg'}),
      'https://example.com/a.jpg',
    );
  });
  testWidgets(
    'zero levels have no badge while server level one remains visible',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              ForumLevelBadge(user: {'level_id': 0}),
              ForumLevelBadge(user: {'level_id': 8, 'is_like': 0}),
            ],
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(home: ForumLevelBadge(user: {'level_id': 1})),
      );
      expect(find.text('1'), findsOneWidget);
    },
  );
  testWidgets(
    'profile has three entries and keeps management inside settings',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ProfilePage())),
      );
      expect(find.text('我的发帖'), findsOneWidget);
      expect(find.text('我的回帖'), findsOneWidget);
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('账号管理'), findsNothing);
      expect(find.text('内容偏好'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
