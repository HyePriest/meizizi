import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba/data/auth_store.dart';
import 'package:tieba/data/local_store.dart';
import 'package:tieba/data/tieba_api.dart';
import 'package:tieba/widgets/forum_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.instance.restore();
    FlutterSecureStorage.setMockInitialValues({
      'baidu_accounts': jsonEncode({
        'active': 'test-user',
        'accounts': [
          {
            'id': 'test-user',
            'user': {'id': 'test-user'},
            'cookies': {'BDUSS': 'fake-cookie'},
          },
        ],
      }),
    });
    await AuthStore.instance.restore();
  });

  test(
    'one sign session serves several forums and rejects account changes',
    () async {
      var logins = 0, signs = 0;
      final api = TiebaApi(
        client: MockClient((request) async {
          if (request.url.path == '/c/s/login') {
            logins++;
            return http.Response(
              '{"error_code":0,"user":{"id":1},"anti":{"tbs":"fake-token"}}',
              200,
            );
          }
          signs++;
          expect(request.bodyFields['tbs'], 'fake-token');
          return http.Response(
            '{"error_code":0,"user_info":{"is_sign_in":1}}',
            200,
          );
        }),
      );
      try {
        final session = await api.prepareSignSession();
        await api.signForum('a', session: session);
        await api.signForum('b', session: session);
        expect(logins, 1);
        expect(signs, 2);
        await AuthStore.instance.save(
          {'BDUSS': 'other-fake-cookie'},
          {'id': 'other'},
        );
        await expectLater(
          api.signForum('c', session: session),
          throwsA(isA<TiebaException>()),
        );
        expect(signs, 2);
      } finally {
        api.close();
      }
    },
  );

  test(
    'confirmed sign status persists, is account specific and expires next day',
    () async {
      final store = LocalStore.instance;
      final today = DateTime(2026, 10, 4, 23, 59);
      await store.markForumSigned('test-user', '数学', now: today);
      await store.restore();
      expect(store.forumSigned('test-user', '数学', now: today), isTrue);
      expect(store.forumSigned('other', '数学', now: today), isFalse);
      expect(
        store.forumSigned('test-user', '数学', now: DateTime(2026, 10, 5)),
        isFalse,
      );
    },
  );

  testWidgets('a bulk sign result immediately updates the forum sign button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SignButton(name: '数学')),
      ),
    );
    expect(find.text('签到'), findsOneWidget);
    await LocalStore.instance.markForumSigned('test-user', '数学');
    await tester.pump();
    expect(find.text('已签到'), findsOneWidget);
  });

  test(
    'public connections preserve list contents and distinct pagination shapes',
    () async {
      final api = TiebaApi(
        client: MockClient((request) async {
          expect(
            request.bodyFields[request.url.path == '/c/f/forum/like'
                ? 'friend_uid'
                : 'uid'],
            '123',
          );
          final data = request.url.path == '/c/f/forum/like'
              ? {
                  'forum_list': {
                    'gconforum': [
                      {'name': 'a'},
                    ],
                    'non-gconforum': [
                      {'name': 'b'},
                    ],
                  },
                  'has_more': '1',
                }
              : request.url.path == '/c/u/fans/page'
              ? {
                  'user_list': [
                    {'id': 2},
                  ],
                  'page': {'has_more': '1'},
                }
              : {
                  'follow_list': [
                    {'id': 3},
                  ],
                  'has_more': 1,
                };
          return http.Response(jsonEncode({'error_code': 0, ...data}), 200);
        }),
      );
      try {
        final forums = await api.userForums('123', 1);
        expect(forums.items.length, 2);
        expect(forums.hasMore, isTrue);
        expect((await api.userFollows('123', 1)).items.single['id'], 3);
        expect((await api.userFollows('123', 1, fans: true)).hasMore, isTrue);
      } finally {
        api.close();
      }
    },
  );
}
