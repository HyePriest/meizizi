import 'emoji_registry.dart';

export 'emoji_registry.dart' show emojiNames;

enum EmojiPack { tieba, baidu, bear, unknown }

class EmojiFace {
  const EmojiFace({
    required this.id,
    required this.label,
    required this.pack,
    required this.assets,
    required this.urls,
  });
  final String id, label;
  final EmojiPack pack;
  final List<String> assets, urls;
  String get asset => assets.isEmpty ? '' : assets.first;
  String get fallback => '[${label.isEmpty ? '表情' : label}]';
}

// Only intentional equivalents cross packs. Unknown faces keep their own art.
const _classicEquivalents = <String, String>{
  '微笑': '呵呵',
  '大笑': '哈哈',
  '笑哭': '笑尿',
  '哭笑': '笑尿',
  '略略略': '吐舌',
  '发怒': '怒',
  '流泪': '泪',
  '大哭': '泪',
  '赞同': '真棒',
  '爱钱': '钱',
  '色': '花心',
  '强颜欢笑': '勉强',
  '抠鼻': '挖鼻',
  '啤酒': '喝酒',
  '心': '爱心',
  '鲜花': '玫瑰',
  '生日蛋糕': '蛋糕',
  '亲吻': '么么哒',
  '亲亲': '么么哒',
  '偷笑': '捂嘴笑',
  '坏笑': '阴险',
  '尬笑': '勉强',
  '庆祝': '欢呼',
};
final _modernEquivalents = <String, String>{
  for (final e in _classicEquivalents.entries)
    if (modernEmojiFilesByName.containsKey(e.key)) e.value: e.key,
};
final _wire = RegExp(
  r'(image_emoticon[0-9]*|shoubai_emoji_face_[0-9]+|bearchildren_[0-9]+)',
);
final _oldUrl = RegExp(r'/face/i_f([0-9]+)\.', caseSensitive: false);
final _textTokens = RegExp(r'#\(([^()\n]+)\)|\(#([^()\n]+)\)|\[([^\[\]\n]+)\]');

String _text(dynamic v) => v == null ? '' : '$v'.trim();
String _decode(String v) {
  try {
    return Uri.decodeComponent(v);
  } catch (_) {
    return v;
  }
}

String _cleanName(String raw) {
  final value = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
  final token = _textTokens.firstMatch(value);
  return token != null && token.start == 0 && token.end == value.length
      ? (token[1] ?? token[2] ?? token[3]!).trim()
      : value;
}

String _readId(String raw) {
  final value = _decode(raw);
  final match = _wire.firstMatch(value);
  if (match != null) {
    final id = match[0]!;
    if (id.startsWith('image_emoticon')) {
      return 'image_emoticon${int.tryParse(id.substring('image_emoticon'.length)) ?? 1}';
    }
    final split = id.lastIndexOf('_');
    final n = int.tryParse(id.substring(split + 1));
    if (n == null) return '';
    return '${id.substring(0, split + 1)}${'$n'.padLeft(2, '0')}';
  }
  final old = _oldUrl.firstMatch(value);
  return old == null ? '' : 'image_emoticon${int.tryParse(old[1]!) ?? 1}';
}

String _imageUrl(dynamic raw) {
  var value = _text(raw).replaceAll('&amp;', '&');
  if (value.startsWith('//')) value = 'https:$value';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      !['http', 'https'].contains(uri.scheme))
    return '';
  return uri.replace(scheme: 'https').toString();
}

String _urlName(String value) {
  final uri = Uri.tryParse(_imageUrl(value));
  if (uri == null || uri.host != 'baidubox-emoji.cdn.bcebos.com') return '';
  final segment = _decode(uri.path).split('/').last;
  final end = segment.lastIndexOf('].');
  return segment.startsWith('[') && end > 1 ? segment.substring(1, end) : '';
}

EmojiPack _pack(String id) {
  if (id.startsWith('image_emoticon')) return EmojiPack.tieba;
  if (id.startsWith('shoubai_emoji_face_')) return EmojiPack.baidu;
  if (id.startsWith('bearchildren_')) return EmojiPack.bear;
  return EmojiPack.unknown;
}

EmojiFace resolveEmoji(Map<String, dynamic> part) {
  var id = '';
  for (final key in ['text', 'emoji_id', 'id', 'src', 'cdn_src', 'url', 'c']) {
    id = _readId(_text(part[key]));
    if (id.isNotEmpty) break;
  }
  var name = '';
  for (final key in ['c', 'alt', 'name', 'text']) {
    final value = _text(part[key]);
    if (value.isNotEmpty &&
        _readId(value).isEmpty &&
        _imageUrl(value).isEmpty) {
      name = _cleanName(value);
      break;
    }
  }
  for (final key in ['src', 'cdn_src', 'url', 'text']) {
    final label = _urlName(_text(part[key]));
    if (label.isNotEmpty) {
      if (name.isEmpty) name = label;
      break;
    }
  }
  if (id.isEmpty) {
    final baidu =
        part['_emoji_pack'] == 'baidu' ||
        _text(part['text']).startsWith('[') ||
        _text(part['c']).startsWith('[');
    id =
        (baidu
            ? baiduEmojiNames[name] ?? emojiNames[name]
            : emojiNames[name] ?? baiduEmojiNames[name]) ??
        '';
  }
  name = emojiLabelsById[id] ?? name;
  final pack = _pack(id);
  final classicId = pack == EmojiPack.tieba
      ? id
      : emojiNames[_classicEquivalents[name] ?? name] ?? '';
  final modernName = modernEmojiFilesByName.containsKey(name)
      ? name
      : _modernEquivalents[name] ?? name;
  final assets = <String>{
    if (classicId.startsWith('image_emoticon') &&
        emojiFilesById[classicId] != null)
      emojiFilesById[classicId]!,
    if (modernEmojiFilesByName[modernName] != null)
      modernEmojiFilesByName[modernName]!,
    if (emojiFilesById[id] != null) emojiFilesById[id]!,
  };
  final urls = <String>{
    if (modernName.isNotEmpty &&
        (pack == EmojiPack.baidu ||
            modernEmojiFilesByName.containsKey(modernName)))
      Uri.https(
        'baidubox-emoji.cdn.bcebos.com',
        '/imgs/[$modernName].png',
      ).toString(),
    for (final key in ['src', 'cdn_src', 'url', 'text'])
      if (_imageUrl(part[key]).isNotEmpty) _imageUrl(part[key]),
    if (id.isNotEmpty) ...[
      'https://tb2.bdstatic.com/tb/editor/images/client/$id.png',
      'https://tb2.bdstatic.com/tb/editor/images/client/$id.gif',
      if (pack == EmojiPack.tieba)
        'https://tb2.bdstatic.com/tb/editor/images/face/i_f${id.substring('image_emoticon'.length)}.png',
    ],
  };
  return EmojiFace(
    id: id,
    label: name,
    pack: pack,
    assets: List.unmodifiable(assets),
    urls: List.unmodifiable(urls),
  );
}

String emojiId(Map<String, dynamic> part) => resolveEmoji(part).id;
String emojiAsset(Map<String, dynamic> part) => resolveEmoji(part).asset;
List<String> emojiUrls(Map<String, dynamic> part) => resolveEmoji(part).urls;

bool isEmojiImage(String src, {String label = '', bool smileyClass = false}) =>
    smileyClass ||
    _readId(src).isNotEmpty ||
    _urlName(src).isNotEmpty ||
    (label.startsWith('#(') && resolveEmoji({'c': label}).assets.isNotEmpty);

List<Map<String, dynamic>> expandTextEmoji(String text) {
  final parts = <Map<String, dynamic>>[];
  var offset = 0;
  for (final match in _textTokens.allMatches(text)) {
    final name = (match[1] ?? match[2] ?? match[3]!).trim();
    final part = <String, dynamic>{
      'type': 2,
      'c': name,
      '_emoji_pack': match[3] == null ? 'tieba' : 'baidu',
    };
    final face = resolveEmoji(part);
    if (face.id.isEmpty && face.assets.isEmpty) continue;
    if (match.start > offset)
      parts.add({'type': 0, 'text': text.substring(offset, match.start)});
    parts.add({...part, 'text': face.id});
    offset = match.end;
  }
  if (offset < text.length)
    parts.add({'type': 0, 'text': text.substring(offset)});
  return parts;
}
