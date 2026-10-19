import 'package:flutter/material.dart';

import '../data/emoji.dart';

/// The same ordered source list is used on every post surface. Each failed
/// image advances to the next source, including when a bundled asset is missing.
class TiebaEmoji extends StatelessWidget {
  const TiebaEmoji({super.key, required this.part, this.size = 24});
  final Map<String, dynamic> part;
  final double size;

  @override
  Widget build(BuildContext context) {
    final face = resolveEmoji(part);
    Widget fallback() =>
        Text(face.fallback, style: TextStyle(fontSize: size * .65));
    Widget load(int index) {
      if (index >= face.assets.length + face.urls.length) return fallback();
      if (index < face.assets.length) {
        final path = face.assets[index];
        return Image.asset(
          path,
          key: ValueKey('asset:$path'),
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => load(index + 1),
        );
      }
      final url = face.urls[index - face.assets.length];
      return Image.network(
        url,
        key: ValueKey('url:$url'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        headers: const {'Referer': 'https://tieba.baidu.com/'},
        errorBuilder: (_, _, _) => load(index + 1),
      );
    }

    return Semantics(
      label: face.fallback,
      image: true,
      child: ExcludeSemantics(child: load(0)),
    );
  }
}
