import 'models.dart';

// Default Tieba face names. The wire identifier is preferred over the label.
const emojiNames = <String, String>{
  '呵呵': 'image_emoticon1',
  '哈哈': 'image_emoticon2',
  '吐舌': 'image_emoticon3',
  '啊': 'image_emoticon4',
  '酷': 'image_emoticon5',
  '怒': 'image_emoticon6',
  '开心': 'image_emoticon7',
  '汗': 'image_emoticon8',
  '泪': 'image_emoticon9',
  '黑线': 'image_emoticon10',
  '鄙视': 'image_emoticon11',
  '不高兴': 'image_emoticon12',
  '真棒': 'image_emoticon13',
  '钱': 'image_emoticon14',
  '疑问': 'image_emoticon15',
  '阴险': 'image_emoticon16',
  '吐': 'image_emoticon17',
  '咦': 'image_emoticon18',
  '委屈': 'image_emoticon19',
  '花心': 'image_emoticon20',
  '呼~': 'image_emoticon21',
  '笑眼': 'image_emoticon22',
  '冷': 'image_emoticon23',
  '太开心': 'image_emoticon24',
  '滑稽': 'image_emoticon25',
  '勉强': 'image_emoticon26',
  '狂汗': 'image_emoticon27',
  '乖': 'image_emoticon28',
  '睡觉': 'image_emoticon29',
  '惊哭': 'image_emoticon30',
  '生气': 'image_emoticon31',
  '惊讶': 'image_emoticon32',
  '喷': 'image_emoticon33',
  '爱心': 'image_emoticon34',
  '心碎': 'image_emoticon35',
  '玫瑰': 'image_emoticon36',
  '礼物': 'image_emoticon37',
  '彩虹': 'image_emoticon38',
  '星星月亮': 'image_emoticon39',
  '太阳': 'image_emoticon40',
  '钱币': 'image_emoticon41',
  '灯泡': 'image_emoticon42',
  '茶杯': 'image_emoticon43',
  '蛋糕': 'image_emoticon44',
  '音乐': 'image_emoticon45',
  'haha': 'image_emoticon46',
  '胜利': 'image_emoticon47',
  '大拇指': 'image_emoticon48',
  '弱': 'image_emoticon49',
  'OK': 'image_emoticon50',
  '小乖': 'image_emoticon66',
  '捂嘴笑': 'image_emoticon67',
  '你懂的': 'image_emoticon68',
  '笑尿': 'image_emoticon69',
  '挖鼻': 'image_emoticon70',
  '噗': 'image_emoticon89',
};

String emojiId(Json part) {
  for (final value in [part['text'], part['src'], part['c']]) {
    final match = RegExp(r'image_emoticon[\w]*').firstMatch('$value');
    if (match != null) {
      return match[0] == 'image_emoticon' ? 'image_emoticon1' : match[0]!;
    }
  }
  final label = firstText([part['c'], part['text']])
      .replaceAll(RegExp(r'[#()\[\]]'), '');
  return emojiNames[label] ?? '';
}

List<String> emojiUrls(Json part) {
  final id = emojiId(part);
  final urls = <String>[
    for (final key in ['src', 'cdn_src', 'url', 'text'])
      if (httpsImage(part[key]).isNotEmpty) httpsImage(part[key]),
    if (id.isNotEmpty)
      'https://tb2.bdstatic.com/tb/editor/images/client/$id.png',
    if (id.isNotEmpty)
      'https://tb2.bdstatic.com/tb/editor/images/client/$id.gif',
    if (id.isNotEmpty)
      'https://tb2.bdstatic.com/tb/editor/images/face/i_f${id.replaceFirst('image_emoticon', '')}.png',
  ];
  // The unnumbered legacy face is the first face; its old URL is broken.
  return urls
      .map(
        (url) => url.replaceAll(
          RegExp(r'image_emoticon\.(png|gif)'),
          'image_emoticon1.png',
        ),
      )
      .toSet()
      .toList();
}

List<Json> expandTextEmoji(String text) {
  final parts = <Json>[];
  final tokens = RegExp(r'#\(([^)]+)\)|\(#([^)]+)\)|\[([^\]]+)\]');
  var offset = 0;
  for (final match in tokens.allMatches(text)) {
    final label = match[1] ?? match[2] ?? match[3]!;
    final id = emojiNames[label];
    if (id == null) continue;
    if (match.start > offset)
      parts.add({'type': 0, 'text': text.substring(offset, match.start)});
    parts.add({'type': 2, 'text': id, 'c': label});
    offset = match.end;
  }
  if (offset < text.length)
    parts.add({'type': 0, 'text': text.substring(offset)});
  return parts;
}
