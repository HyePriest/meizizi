import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

// Field numbers from tbclient.PbPage and its imported messages.
// Unknown fields are skipped so server additions do not affect reading.
typedef _Field = (String, String, bool);
const _schemas = <String, Map<int, _Field>>{
  'bawuResponse': {
    1: ('data', 'bawuData', false),
    2: ('error', 'error', false),
  },
  'bawuData': {1: ('team', 'bawuTeam', false)},
  'bawuTeam': {1: ('total', 'int', false), 2: ('groups', 'bawuGroup', true)},
  'bawuGroup': {1: ('role', 'string', false), 2: ('users', 'bawuUser', true)},
  'bawuUser': {
    2: ('id', 'int', false),
    4: ('forum_role', 'string', false),
    5: ('portrait', 'string', false),
    6: ('level_id', 'int', false),
    8: ('name', 'string', false),
    9: ('name_show', 'string', false),
  },
  'floorResponse': {
    1: ('error', 'error', false),
    2: ('data', 'floorData', false),
  },
  'floorData': {
    1: ('page', 'page', false),
    3: ('post', 'post', false),
    4: ('subpost_list', 'subpost', true),
    5: ('thread', 'thread', false),
    6: ('forum', 'forum', false),
  },
  'subpost': {
    1: ('id', 'int', false),
    2: ('content', 'content', true),
    3: ('time', 'int', false),
    4: ('author_id', 'int', false),
    6: ('floor', 'int', false),
    7: ('author', 'user', false),
    9: ('agree', 'agree', false),
    13: ('footer', 'string', false),
  },
  'video': {
    2: ('video_url', 'string', false),
    3: ('video_duration', 'int', false),
    4: ('video_width', 'int', false),
    5: ('video_height', 'int', false),
    6: ('thumbnail_url', 'string', false),
  },
  'pollResponse': {1: ('error', 'error', false)},
  'poll': {
    1: ('type', 'int', false),
    2: ('is_multi', 'int', false),
    3: ('total_num', 'int', false),
    4: ('options_count', 'int', false),
    5: ('is_polled', 'int', false),
    6: ('polled_value', 'string', false),
    7: ('tips', 'string', false),
    8: ('end_time', 'int', false),
    9: ('options', 'pollOption', true),
    10: ('status', 'int', false),
    11: ('total_poll', 'int', false),
    12: ('title', 'string', false),
  },
  'pollOption': {
    1: ('id', 'int', false),
    2: ('num', 'int', false),
    3: ('text', 'string', false),
    4: ('image', 'string', false),
  },
  'response': {1: ('error', 'error', false), 2: ('data', 'data', false)},
  'error': {1: ('errorno', 'int', false), 2: ('errmsg', 'string', false)},
  'data': {
    2: ('forum', 'forum', false),
    3: ('page', 'page', false),
    6: ('post_list', 'post', true),
    8: ('thread', 'thread', false),
    13: ('user_list', 'user', true),
    38: ('first_floor_post', 'post', false),
    49: ('pb_sort_info', 'sort', true),
    50: ('sort_type', 'int', false),
  },
  'sort': {1: ('sort_type', 'int', false), 2: ('sort_name', 'string', false)},
  'forum': {1: ('id', 'int', false), 2: ('name', 'string', false)},
  'page': {
    3: ('current_page', 'int', false),
    4: ('total_count', 'int', false),
    5: ('total_page', 'int', false),
    6: ('has_more', 'int', false),
  },
  'post': {
    1: ('id', 'int', false),
    3: ('floor', 'int', false),
    4: ('time', 'int', false),
    5: ('content', 'content', true),
    13: ('sub_post_number', 'int', false),
    15: ('sub_post_list', 'embeddedReplies', false),
    19: ('author_id', 'int', false),
    23: ('author', 'user', false),
    29: ('video_info', 'video', false),
    37: ('agree', 'agree', false),
  },
  'embeddedReplies': {2: ('sub_post_list', 'subpost', true)},
  'user': {
    2: ('id', 'int', false),
    3: ('name', 'string', false),
    4: ('name_show', 'string', false),
    5: ('portrait', 'string', false),
    23: ('level_id', 'int', false),
    25: ('is_bawu', 'int', false),
    26: ('bawu_type', 'string', false),
    125: ('level_name', 'string', false),
    127: ('ip_address', 'string', false),
  },
  'agree': {
    1: ('agree_num', 'int', false),
    2: ('has_agree', 'int', false),
    3: ('agree_type', 'int', false),
    4: ('disagree_num', 'int', false),
  },
  'thread': {
    1: ('id', 'int', false),
    3: ('title', 'string', false),
    4: ('reply_num', 'int', false),
    18: ('author', 'user', false),
    27: ('fid', 'int', false),
    28: ('fname', 'string', false),
    74: ('poll_info', 'poll', false),
    79: ('video_info', 'video', false),
    126: ('agree', 'agree', false),
  },
  'content': {
    1: ('type', 'int', false),
    2: ('text', 'string', false),
    3: ('link', 'string', false),
    4: ('src', 'string', false),
    5: ('bsize', 'string', false),
    8: ('cdn_src', 'string', false),
    9: ('big_cdn_src', 'string', false),
    11: ('c', 'string', false),
    12: ('voice_md5', 'string', false),
    13: ('during_time', 'int', false),
    18: ('width', 'int', false),
    19: ('height', 'int', false),
    25: ('origin_src', 'string', false),
    27: ('origin_size', 'int', false),
  },
};

class _Reader {
  _Reader(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      if (offset >= bytes.length) {
        throw const FormatException('Truncated protobuf');
      }
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte < 128) return value;
    }
    throw const FormatException('Invalid protobuf integer');
  }

  Uint8List take(int count) {
    if (count < 0 || count > bytes.length - offset) {
      throw const FormatException('Invalid protobuf length');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + count);
    offset += count;
    return result;
  }
}

Json decodePostResponse(Uint8List bytes) => _decode(bytes, 'response');

Json _decode(Uint8List bytes, String type) {
  final reader = _Reader(bytes), schema = _schemas[type]!;
  final result = <String, dynamic>{};
  while (reader.offset < bytes.length) {
    final tag = reader.varint(), wire = tag & 7;
    if (tag >> 3 == 0) throw const FormatException('Invalid protobuf tag');
    final field = schema[tag >> 3];
    dynamic value;
    if (wire == 0) {
      value = reader.varint();
      if (field != null && field.$2 != 'int') {
        throw const FormatException('Invalid protobuf type');
      }
    } else if (wire == 2) {
      final raw = reader.take(reader.varint());
      if (field == null) continue;
      if (field.$2 == 'int') {
        throw const FormatException('Invalid protobuf type');
      }
      value = field.$2 == 'string' ? utf8.decode(raw) : _decode(raw, field.$2);
    } else if (wire == 1 || wire == 5) {
      reader.take(wire == 1 ? 8 : 4);
      continue;
    } else {
      throw const FormatException('Unsupported protobuf wire type');
    }
    if (field == null) continue;
    if (field.$3) {
      (result.putIfAbsent(field.$1, () => <dynamic>[]) as List).add(value);
    } else {
      result[field.$1] = value;
    }
  }
  // Proto3 omits zero values. Preserve the forum's zero level when merging users.
  if (type == 'user') result.putIfAbsent('level_id', () => 0);
  return result;
}

List<int> _varint(int value) {
  if (value < 0) throw const FormatException('Negative protobuf integer');
  final bytes = <int>[];
  while (value > 127) {
    bytes.add((value & 127) | 128);
    value >>= 7;
  }
  return [...bytes, value];
}

List<int> _int(int field, int value) => [
  ..._varint(field << 3),
  ..._varint(value),
];
List<int> _bytes(int field, List<int> value) => [
  ..._varint((field << 3) | 2),
  ..._varint(value.length),
  ...value,
];

Uint8List encodeHotPosts(
  String threadId,
  int page, {
  required String bduss,
  required String stoken,
  required String cuid,
  bool onlyAuthor = false,
}) {
  final common = [
    ..._int(1, 2),
    ..._bytes(2, utf8.encode('22.12.1.0')),
    ..._bytes(7, utf8.encode(cuid)),
    if (bduss.isNotEmpty) ..._bytes(10, utf8.encode(bduss)),
    if (stoken.isNotEmpty) ..._bytes(30, utf8.encode(stoken)),
  ];
  final data = [
    ..._int(4, int.parse(threadId)),
    ..._int(5, onlyAuthor ? 1 : 0),
    ..._int(6, 2),
    ..._int(8, 1),
    ..._int(9, 4),
    ..._int(13, 20),
    ..._int(17, 2),
    ..._int(18, page),
    ..._bytes(19, utf8.encode('tb_frslist')),
    ..._bytes(25, common),
    ..._int(74, 1),
    ..._int(75, 2),
  ];
  return Uint8List.fromList(_bytes(1, data));
}

Json decodeFloorResponse(Uint8List bytes) => _decode(bytes, 'floorResponse');
Json decodeBawuResponse(Uint8List bytes) => _decode(bytes, 'bawuResponse');
Uint8List encodeBawu(String fid) => Uint8List.fromList(
  _bytes(1, [
    ..._bytes(1, _bytes(2, utf8.encode('22.12.1.0'))),
    ..._int(2, int.parse(fid)),
  ]),
);
Json decodePollResponse(Uint8List bytes) => _decode(bytes, 'pollResponse');

Uint8List encodePoll(
  String threadId,
  String forumId,
  List<int> options, {
  required String bduss,
  required String stoken,
  required String cuid,
}) {
  final common = [
    ..._int(1, 2),
    ..._bytes(2, utf8.encode('22.12.1.0')),
    ..._bytes(7, utf8.encode(cuid)),
    ..._bytes(10, utf8.encode(bduss)),
    if (stoken.isNotEmpty) ..._bytes(30, utf8.encode(stoken)),
  ];
  // AddPoll uses one-based option numbers, encoded as a comma-separated string.
  return Uint8List.fromList(
    _bytes(1, [
      ..._int(1, int.parse(threadId)),
      ..._bytes(2, utf8.encode(options.join(','))),
      ..._bytes(3, common),
      ..._int(4, int.parse(forumId)),
    ]),
  );
}

Uint8List encodeFloor(
  String tid,
  String pid,
  int page, {
  required String bduss,
  required String stoken,
  required String cuid,
  String? targetReply,
}) {
  final common = [
    ..._int(1, 2),
    ..._bytes(2, utf8.encode('22.12.1.0')),
    ..._bytes(7, utf8.encode(cuid)),
    if (bduss.isNotEmpty) ..._bytes(10, utf8.encode(bduss)),
    if (stoken.isNotEmpty) ..._bytes(30, utf8.encode(stoken)),
  ];
  return Uint8List.fromList(
    _bytes(1, [
      ..._int(1, int.parse(tid)),
      ..._int(2, int.parse(pid)),
      if (targetReply != null) ..._int(3, int.parse(targetReply)),
      if (targetReply == null) ..._int(4, page),
      ..._bytes(9, common),
    ]),
  );
}
