import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'emoji.dart';

const _ink = Color(0xff202733);
const _muted = Color(0xff7a8492);
const _blue = Color(0xff3877c4);

Future<Uint8List> renderForumPoster({
  required String name,
  required String url,
  required Json data,
  http.Client? imageClient,
}) async {
  final client = imageClient ?? http.Client();
  final art = <ui.Image?>[];
  final labels = <TextPainter>[];
  void label(
    Canvas canvas,
    String text,
    Offset position,
    double size, {
    Color color = _ink,
    FontWeight weight = FontWeight.normal,
    double width = 624,
    int lines = 1,
  }) {
    final painter = _text(
      text,
      size,
      color: color,
      weight: weight,
      width: width,
      lines: lines,
      fontFamily: 'sans-serif',
    );
    labels.add(painter);
    painter.paint(canvas, position);
  }

  String count(dynamic value) {
    final n = number(value);
    return n < 10000
        ? '$n'
        : '${(n / 10000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}w';
  }

  try {
    art.addAll(
      await Future.wait([
        _remoteImage(client, forumCoverUrl(data), width: 1440),
        _remoteImage(client, httpsImage(data['avatar']), width: 224),
      ]),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 720, 960),
      Paint()..color = const Color(0xfff3f6f8),
    );
    const coverRect = Rect.fromLTWH(0, 0, 720, 380);
    canvas.drawRect(
      coverRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff246b5b), Color(0xff172735)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(coverRect),
    );
    if (art[0] != null)
      paintImage(
        canvas: canvas,
        rect: coverRect,
        image: art[0]!,
        fit: BoxFit.cover,
      );
    canvas.drawRect(
      coverRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: .2),
            Colors.black.withValues(alpha: .7),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(coverRect),
    );
    label(
      canvas,
      '百度贴吧 · 社区分享',
      const Offset(48, 48),
      20,
      color: Colors.white70,
    );
    label(
      canvas,
      '$name吧',
      const Offset(48, 118),
      42,
      color: Colors.white,
      weight: FontWeight.w700,
      lines: 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 292, 672, 552),
        const Radius.circular(28),
      ),
      Paint()..color = Colors.white,
    );
    final avatarRect = const Rect.fromLTWH(48, 252, 104, 104);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(avatarRect, const Radius.circular(22)),
    );
    if (art[1] != null) {
      paintImage(
        canvas: canvas,
        rect: avatarRect,
        image: art[1]!,
        fit: BoxFit.cover,
      );
    } else {
      canvas.drawRect(avatarRect, Paint()..color = const Color(0xffdcece6));
      label(
        canvas,
        '吧',
        const Offset(78, 268),
        40,
        color: const Color(0xff246b5b),
      );
    }
    canvas.restore();
    label(
      canvas,
      '$name吧',
      const Offset(176, 308),
      26,
      weight: FontWeight.w600,
      width: 472,
    );
    label(canvas, '关注', const Offset(48, 392), 18, color: _muted);
    label(
      canvas,
      count(data['member_num']),
      const Offset(48, 422),
      34,
      weight: FontWeight.w600,
      width: 260,
    );
    canvas.drawLine(
      const Offset(348, 398),
      const Offset(348, 466),
      Paint()..color = const Color(0xffe6ece9),
    );
    label(canvas, '帖子', const Offset(392, 392), 18, color: _muted, width: 256);
    label(
      canvas,
      count(data['thread_num']),
      const Offset(392, 422),
      34,
      weight: FontWeight.w600,
      width: 256,
    );
    label(canvas, '吧简介', const Offset(48, 510), 18, color: _muted);
    label(canvas, forumDescription(data), const Offset(48, 548), 26, lines: 6);
    canvas.drawLine(
      const Offset(48, 790),
      const Offset(648, 790),
      Paint()..color = const Color(0xffe6ece9),
    );
    label(canvas, '来自美滋滋', const Offset(48, 808), 15, color: _muted);
    label(canvas, '吧链接', const Offset(48, 868), 16, color: _muted);
    label(
      canvas,
      Uri.decodeFull(url),
      const Offset(48, 898),
      15,
      color: const Color(0xff246b5b),
      lines: 2,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1440, 1920);
    picture.dispose();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法生成吧分享海报');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    if (imageClient == null) client.close();
    for (final image in art) {
      image?.dispose();
    }
    for (final painter in labels) {
      painter.dispose();
    }
  }
}

TextPainter _text(
  String value,
  double size, {
  Color color = _ink,
  FontWeight weight = FontWeight.normal,
  int? lines,
  double width = 576,
  String? fontFamily,
}) => TextPainter(
  text: TextSpan(
    text: value,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: 1.45,
      fontFamily: fontFamily,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: lines,
  ellipsis: lines == null ? null : '…',
)..layout(maxWidth: width);

Future<ui.Image?> _remoteImage(
  http.Client client,
  String url, {
  int width = 640,
}) async {
  if (url.isEmpty) return null;
  try {
    final response = await client
        .send(
          http.Request('GET', Uri.parse(url))
            ..headers.addAll({
              'Referer': 'https://tieba.baidu.com/',
              'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36',
            }),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > 8 * 1024 * 1024)
      return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 4),
    )) {
      bytes.add(chunk);
      if (bytes.length > 8 * 1024 * 1024) return null;
    }
    final codec = await ui.instantiateImageCodec(
      bytes.takeBytes(),
      targetWidth: width,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Two local layouts: a post card and a compact, reusable comment capture.
Future<Uint8List> renderShareImage({
  required String title,
  required String forum,
  required String url,
  required Json data,
  required bool comment,
}) async {
  List<Json> parts = [];
  for (final value in [
    data['content'],
    data['rich_abstract'],
    data['abstract'],
  ]) {
    parts = contentParts(value);
    if (parts.isNotEmpty) break;
  }
  final user = object(data['author']);
  final photos = threadImages(data).take(2).toList();
  final client = http.Client();
  final loaded = <ui.Image?>[];
  final emojiArt = <String, ui.Image>{};
  TextPainter? body;
  try {
    loaded.addAll(
      await Future.wait([
        _remoteImage(client, avatarUrl(user), width: 96),
        for (final photo in photos)
          _remoteImage(client, '${photo['original']}'),
      ]),
    );
    final spans = <InlineSpan>[];
    final emojiSlots = <ui.Image>[];
    var length = 0;
    for (final part in parts) {
      if (length >= 1800) {
        spans.add(const TextSpan(text: '…'));
        break;
      }
      final type = number(part['type']);
      if (type == 52 || type == 3 || type == 20) continue;
      if (type == 2) {
        final face = resolveEmoji(part);
        final asset = face.asset;
        if (asset.isNotEmpty && emojiArt.length < 24) {
          try {
            if (!emojiArt.containsKey(asset)) {
              final bytes = await rootBundle.load(asset);
              final codec = await ui.instantiateImageCodec(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
                targetWidth: 64,
              );
              try {
                emojiArt[asset] = (await codec.getNextFrame()).image;
              } finally {
                codec.dispose();
              }
            }
            emojiSlots.add(emojiArt[asset]!);
            spans.add(
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox.square(dimension: 28),
              ),
            );
            continue;
          } catch (_) {
            /* Keep the readable face label if its art is unavailable. */
          }
        }
        spans.add(TextSpan(text: face.fallback));
      } else {
        var value = type == 5
            ? '[视频]'
            : type == 10
            ? '[语音]'
            : plainText(part['text']);
        if (type == 4 && value.isEmpty) value = '该用户';
        if (value.length > 1800 - length) {
          var end = 1800 - length;
          if (end > 0 &&
              value.codeUnitAt(end - 1) >= 0xd800 &&
              value.codeUnitAt(end - 1) <= 0xdbff)
            end--;
          value = '${value.substring(0, end)}…';
        }
        length += value.length;
        spans.add(
          TextSpan(
            text: value,
            style: type == 4 ? const TextStyle(color: _blue) : null,
          ),
        );
      }
    }
    body = TextPainter(
      text: TextSpan(
        children: spans,
        style: TextStyle(
          color: _ink,
          fontSize: comment ? 23 : 21,
          height: 1.55,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 42,
      ellipsis: '…',
    );
    body.setPlaceholderDimensions([
      for (final _ in emojiSlots)
        const PlaceholderDimensions(
          size: Size.square(28),
          alignment: PlaceholderAlignment.middle,
        ),
    ]);
    body.layout(maxWidth: 576);
    final heading = _text(title, 28, weight: FontWeight.w700, lines: 6);
    final name = _text(
      author(user),
      18,
      weight: FontWeight.w600,
      color: _blue,
      width: 510,
      lines: 2,
    );
    final meta = _text(
      [
        commentTime(data['time'] ?? data['create_time']),
        postIp(data, user),
      ].where((value) => value.isNotEmpty && value != '时间未知').join(' · '),
      14,
      color: _muted,
      width: 510,
    );
    final headerHeight = 28 + name.height + meta.height;
    final photoHeights = <double>[
      for (final image in loaded.skip(1))
        image == null
            ? 32
            : (image.height / image.width * 576).clamp(0.0, 460.0),
    ];
    final height =
        (32 +
                (comment ? 0 : 64 + heading.height + 24) +
                headerHeight +
                16 +
                (spans.isEmpty ? 0 : body.height) +
                photoHeights.fold<double>(0, (sum, h) => sum + h + 12) +
                (comment ? 60 : 92))
            .ceilToDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 640, height),
      Paint()..color = Colors.white,
    );
    double y = 28;
    if (!comment) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(32, 28, 32, 32),
          const Radius.circular(9),
        ),
        Paint()..color = _blue,
      );
      _text(
        '吧',
        20,
        color: Colors.white,
        weight: FontWeight.w700,
        width: 30,
      ).paint(canvas, const Offset(37, 29));
      _text(
        forum.isEmpty ? '帖子分享' : '$forum吧',
        18,
        color: _blue,
        weight: FontWeight.w600,
      ).paint(canvas, const Offset(76, 30));
      y += 64;
      heading.paint(canvas, Offset(32, y));
      y += heading.height + 24;
    }
    final avatarRect = Rect.fromLTWH(32, y + 2, 46, 46);
    canvas.save();
    canvas.clipPath(Path()..addOval(avatarRect));
    final avatar = loaded.first;
    if (avatar != null) {
      paintImage(
        canvas: canvas,
        rect: avatarRect,
        image: avatar,
        fit: BoxFit.cover,
      );
    } else {
      canvas.drawRect(avatarRect, Paint()..color = const Color(0xffe8eef6));
      canvas.drawCircle(
        Offset(55, y + 17),
        8,
        Paint()..color = const Color(0xff9cb6d8),
      );
      canvas.drawOval(
        Rect.fromLTWH(39, y + 29, 32, 25),
        Paint()..color = const Color(0xff9cb6d8),
      );
    }
    canvas.restore();
    name.paint(canvas, Offset(92, y));
    meta.paint(canvas, Offset(92, y + name.height + 4));
    y += headerHeight + 10;
    if (spans.isNotEmpty) {
      body.paint(canvas, Offset(32, y));
      final boxes = body.inlinePlaceholderBoxes ?? [];
      for (var i = 0; i < boxes.length && i < emojiSlots.length; i++) {
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(
            32 + boxes[i].left,
            y + boxes[i].top,
            boxes[i].right - boxes[i].left,
            boxes[i].bottom - boxes[i].top,
          ),
          image: emojiSlots[i],
          fit: BoxFit.contain,
        );
      }
      y += body.height + 12;
    }
    for (var i = 1; i < loaded.length; i++) {
      final image = loaded[i], h = photoHeights[i - 1];
      if (image == null) {
        _text('[图片暂未载入]', 15, color: _muted).paint(canvas, Offset(32, y));
      } else {
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(32, y, 576, h),
          image: image,
          fit: BoxFit.contain,
        );
      }
      y += h + 12;
    }
    canvas.drawLine(
      Offset(32, y + 7),
      Offset(608, y + 7),
      Paint()..color = const Color(0xffedf0f4),
    );
    final source = _text(
      forum.isEmpty ? (comment ? '评论' : '帖子') : '$forum吧',
      13,
      color: _muted,
      lines: 1,
      width: 460,
    );
    source.paint(canvas, Offset(32, y + 20));
    if (comment && number(data['floor']) > 0) {
      final floor = _text('${data['floor']}楼', 13, color: _muted);
      floor.paint(canvas, Offset(608 - floor.width, y + 20));
    }
    if (!comment)
      _text(url, 12, color: _muted, lines: 2).paint(canvas, Offset(32, y + 44));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1280, (height * 2).ceil());
    picture.dispose();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法生成分享图片');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    client.close();
    body?.dispose();
    for (final image in loaded) {
      image?.dispose();
    }
    for (final image in emojiArt.values) {
      image.dispose();
    }
  }
}
