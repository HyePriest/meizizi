import 'package:flutter_test/flutter_test.dart';
import 'package:tieba/data/forum_protocol.dart';
import 'package:tieba/data/models.dart';

void main() {
  test(
    'official header images are parsed independently of forum theme art',
    () {
      final data = <String, dynamic>{
        'activityhead': {
          'head_imgs': [
            {
              'type': 2,
              'img_url': 'https://tieba-ares.cdn.bcebos.com/mis/2023-10/1698071262696/c9610ad04d7b.jpg',
            },
          ],
        },
        'forum': {
          'theme_color': {
            'day': {'pattern_image': 'https://example.com/texture.jpg'},
          },
        },
      };
      final header = decodeForumHeaderImage(data);
      expect(header, endsWith('/c9610ad04d7b.jpg'));
      expect(
        forumCoverUrl({...object(data['forum']), 'header_image': header}),
        header,
      );
      expect(decodeForumHeaderImage({'forum': data['forum']}), isEmpty);
    },
  );

  test(
    'missing and invalid header images cannot be replaced by unrelated art',
    () {
      expect(decodeForumHeaderImage({'activityhead': {}}), isEmpty);
      expect(
        decodeForumHeaderImage({
          'activityhead': {
            'head_imgs': [
              {'img_url': ''},
              {'img_url': 'not-an-image'},
              {'img_url': 'javascript:alert(1)'},
            ],
          },
        }),
        isEmpty,
      );
      expect(
        decodeForumHeaderImage({
          'activityhead': {
            'head_imgs': [
              {'img_url': ''},
              {'img_url': 'http://example.com/header.jpg'},
            ],
          },
        }),
        'https://example.com/header.jpg',
      );
    },
  );
}
