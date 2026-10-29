import '../data/platform_session.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../data/emoji.dart';
import '../widgets/tieba_emoji.dart';
import 'login_page.dart';

class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    required this.threadId,
    required this.forumName,
    required this.forumId,
    required this.title,
    this.postId,
    this.replyUid,
    this.building = false,
    this.scrollController,
    this.onExpand,
    this.expanded = false,
    this.onEmojiChanged,
    this.onDrag,
  });
  final String threadId, forumName, forumId, title;
  final String? postId, replyUid;
  final bool building, expanded;
  final ScrollController? scrollController;
  final VoidCallback? onExpand;
  final ValueChanged<bool>? onEmojiChanged;
  final ValueChanged<double>? onDrag;
  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPhoto {
  _ReplyPhoto(this.bytes, this.width, this.height, this.mime);
  final Uint8List bytes;
  final int width, height;
  final String mime;
  String? uploaded;
}

class _ReplyPageState extends State<ReplyPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _api = TiebaApi();
  final _photos = <_ReplyPhoto>[];
  late String _account;
  bool _busy = false, _picking = false, _uncertain = false, _emojiOpen = false;
  String? _error;
  String _sending = '发送中';
  int _emojiPage = 0;

  @override
  void initState() {
    super.initState();
    _account = AuthStore.instance.activeId;
    _text.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _api.close();
    super.dispose();
  }

  void _showEmoji(bool show) {
    setState(() => _emojiOpen = show);
    widget.onEmojiChanged?.call(show);
    if (show) {
      _focus.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  void _insert(String value) {
    if (_busy) return;
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    final content = _text.text.replaceRange(start, end, value);
    if (content.length > 10000) return;
    _text.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  Future<void> _pickImages() async {
    if (_busy || _picking) return;
    if (_photos.length >= 9) {
      setState(() => _error = '每次最多选择 9 张图片');
      return;
    }
    _focus.unfocus();
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      widget.onEmojiChanged?.call(false);
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final selected = await const PlatformSession()
          .invokeListMethod<dynamic>('pickReplyImages');
      if (!mounted) return;
      final images = <_ReplyPhoto>[];
      for (final entry in selected ?? []) {
        if (entry is! Map || entry['bytes'] is! Uint8List) continue;
        final width = number(entry['width']), height = number(entry['height']);
        if (width <= 0 || height <= 0) continue;
        images.add(
          _ReplyPhoto(
            entry['bytes'] as Uint8List,
            width,
            height,
            '${entry['mime']}',
          ),
        );
      }
      setState(() {
        final remaining = 9 - _photos.length;
        _photos.addAll(images.take(remaining));
        if (images.length > remaining) _error = '每次最多选择 9 张图片';
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? '无法打开相册');
    } catch (_) {
      if (mounted) setState(() => _error = '读取图片失败，请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _sameAccount() =>
      AuthStore.instance.isLoggedIn && AuthStore.instance.activeId == _account;

  Future<void> _send() async {
    if (_busy || _picking || _uncertain) return;
    final content = _text.text.trim();
    if (content.isEmpty && _photos.isEmpty) return;
    if (!AuthStore.instance.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (!mounted) return;
      if (_account.isEmpty && AuthStore.instance.isLoggedIn)
        _account = AuthStore.instance.activeId;
      setState(() {});
      return;
    }
    if (_account.isEmpty) _account = AuthStore.instance.activeId;
    if (!_sameAccount()) {
      setState(() => _error = '账号已切换，请关闭后重新打开评论');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _sending = '发送中';
    });
    try {
      for (var i = 0; i < _photos.length; i++) {
        if (!_sameAccount()) throw const TiebaException('账号已切换，请关闭后重新打开评论');
        final photo = _photos[i];
        setState(() => _sending = '上传图片 ${i + 1}/${_photos.length}');
        photo.uploaded ??= await _api.uploadReplyImage(
          bytes: photo.bytes,
          width: photo.width,
          height: photo.height,
          mime: photo.mime,
          forumName: widget.forumName,
        );
        if (!mounted) return;
      }
      if (!_sameAccount()) throw const TiebaException('账号已切换，请关闭后重新打开评论');
      setState(() => _sending = '发送中');
      await _api.reply(
        threadId: widget.threadId,
        forumName: widget.forumName,
        forumId: widget.forumId,
        postId: widget.postId,
        replyUid: widget.replyUid,
        imageCount: _photos.length,
        content: [
          content,
          ..._photos.map((photo) => photo.uploaded!),
        ].where((part) => part.isNotEmpty).join('\n'),
      );
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e is TiebaException ? e.message : '发送失败，请检查网络';
          _uncertain = e is TiebaException && e.uncertain;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photoStrip() => SizedBox(
    height: 82,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) => SizedBox(
        width: 72,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _photos[index].bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 180,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '移除图片',
                onPressed: _busy
                    ? null
                    : () => setState(() => _photos.removeAt(index)),
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorMessage() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
          ),
        ),
        if (_uncertain)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('返回帖子核对结果'),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LoginPage(
                      verificationUrl:
                          'https://tieba.baidu.com/p/${widget.threadId}',
                    ),
                  ),
                ),
          child: const Text('打开官方页面处理验证'),
        ),
      ],
    ),
  );

  Widget _editor() => LayoutBuilder(
    builder: (context, area) => CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: area.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.building && _photos.isNotEmpty) _photoStrip(),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      enabled: !_busy,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      maxLength: 10000,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                      decoration: InputDecoration(
                        hintText: widget.replyUid != null
                            ? '${widget.title}…'
                            : (widget.building ? '为这栋楼添一层…' : '输入评论内容'),
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: .65),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                        isCollapsed: true,
                      ),
                      onTap: () {
                        if (_emojiOpen) _showEmoji(false);
                      },
                    ),
                  ),
                  if (!widget.building && _photos.isNotEmpty) _photoStrip(),
                  if (_error != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            (area.maxHeight - (_photos.isEmpty ? 64 : 146))
                                .clamp(0, area.maxHeight * .35),
                      ),
                      child: SingleChildScrollView(child: _errorMessage()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tools() {
    final colors = Theme.of(context).colorScheme;
    final ready =
        !_busy &&
        !_picking &&
        !_uncertain &&
        (_text.text.trim().isNotEmpty || _photos.isNotEmpty);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _busy
          ? null
          : (details) => widget.onDrag?.call(details.delta.dy),
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          border: widget.building
              ? Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .5),
                    width: .5,
                  ),
                )
              : Border(
                  top: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .5),
                    width: .5,
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: IconTheme(
          data: IconThemeData(
            color: colors.onSurfaceVariant.withValues(alpha: .65),
            size: 24,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: _emojiOpen ? '键盘' : '表情',
                onPressed: _busy ? null : () => _showEmoji(!_emojiOpen),
                icon: Icon(
                  _emojiOpen
                      ? Icons.keyboard_outlined
                      : Icons.emoji_emotions_outlined,
                ),
              ),
              IconButton(
                tooltip: '@',
                onPressed: _busy
                    ? null
                    : () {
                        _insert('@');
                        _showEmoji(false);
                      },
                icon: const Icon(Icons.alternate_email),
              ),
              IconButton(
                tooltip: '从相册添加图片',
                onPressed: _busy || _picking ? null : _pickImages,
                icon: _picking
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: widget.expanded ? '收起' : '展开',
                onPressed: _busy ? null : widget.onExpand,
                icon: Icon(
                  widget.expanded ? Icons.unfold_less : Icons.unfold_more,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: ready ? _send : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.building ? '盖楼' : '发送'),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojis() => SizedBox(
    height: 248,
    child: LayoutBuilder(
      builder: (context, area) {
        final columns = (area.maxWidth / 48).floor().clamp(5, 8);
        final perPage = columns * 4;
        final faces = emojiNames.entries.toList();
        final pages = (faces.length / perPage).ceil();
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                onPageChanged: (index) => setState(() => _emojiPage = index),
                itemCount: pages,
                itemBuilder: (_, page) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 54,
                  ),
                  itemCount: perPage,
                  itemBuilder: (_, index) {
                    final at = page * perPage + index;
                    if (at >= faces.length) return const SizedBox.shrink();
                    final face = faces[at];
                    return Tooltip(
                      message: face.key,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _busy ? null : () => _insert('#(${face.key})'),
                        child: Center(
                          child: TiebaEmoji(
                            part: {'type': 2, 'text': face.value},
                            size: 36,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              height: 16,
              child: Center(
                child: Text(
                  '${_emojiPage + 1} / $pages',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: .55),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final showEmoji =
        _emojiOpen && MediaQuery.viewInsetsOf(context).bottom < 20;
    return PopScope(
      canPop: !_busy && !_picking,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(
          top: widget.building ? Radius.zero : const Radius.circular(14),
          bottom: widget.building ? const Radius.circular(14) : Radius.zero,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (widget.building && showEmoji) _emojis(),
            if (widget.building) _tools(),
            Expanded(child: _editor()),
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _sending,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            if (!widget.building) _tools(),
            if (!widget.building && showEmoji) _emojis(),
          ],
        ),
      ),
    );
  }
}

class ReplyComposerSheet extends StatefulWidget {
  const ReplyComposerSheet({
    super.key,
    required this.builder,
    this.building = false,
  });
  final bool building;
  final Widget Function(
    ScrollController,
    VoidCallback,
    bool,
    ValueChanged<bool>,
    ValueChanged<double>,
  )
  builder;
  @override
  State<ReplyComposerSheet> createState() => _ReplyComposerSheetState();
}

class _ReplyComposerSheetState extends State<ReplyComposerSheet> {
  final _scroll = ScrollController();
  double _fraction = .44;
  double _availableHeight = 1;
  bool _emoji = false, _dragging = false;
  bool get _expanded => _fraction > .8;
  void _toggle() => setState(() {
    _fraction = _expanded ? .44 : .96;
    _dragging = false;
  });
  void _emojiChanged(bool open) => setState(() => _emoji = open);
  void _drag(double delta) => setState(() {
    _dragging = true;
    _fraction =
        (_fraction + (widget.building ? delta : -delta) / _availableHeight)
            .clamp(.3, .96);
  });
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: LayoutBuilder(
        builder: (context, area) {
          _availableHeight = area.maxHeight;
          final minHeight = _emoji ? 430.0 : 230.0;
          final height = (_fraction * area.maxHeight).clamp(
            minHeight.clamp(0, area.maxHeight),
            area.maxHeight,
          );
          return Align(
            alignment: widget.building
                ? Alignment.topCenter
                : Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: _dragging || MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: height.toDouble(),
              width: double.infinity,
              child: widget.builder(
                _scroll,
                _toggle,
                _expanded,
                _emojiChanged,
                _drag,
              ),
            ),
          );
        },
      ),
    ),
  );
}
