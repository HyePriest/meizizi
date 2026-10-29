import '../widgets/app_snack_bar.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_store.dart';
import '../data/theme_colors.dart';
import '../widgets/feed_icons.dart';

class ThemeColorPage extends StatefulWidget {
  const ThemeColorPage({
    super.key,
    this.background = false,
    this.button = false,
  });
  final bool background;
  final bool button;
  @override
  State<ThemeColorPage> createState() => _ThemeColorPageState();
}

class _ThemeColorPageState extends State<ThemeColorPage> {
  late final int _original = widget.background
      ? LocalStore.instance.backgroundColor
      : widget.button
      ? LocalStore.instance.buttonColor
      : LocalStore.instance.themeColor;
  late HSVColor _color = HSVColor.fromColor(Color(_original));
  late final bool _originalFollowsSystem =
      LocalStore.instance.backgroundFollowsSystem;
  late bool _followSystem = widget.background && _originalFollowsSystem;
  bool _saved = false, _saving = false;

  String get _hexColor =>
      '#${_color.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _copyColor() async {
    await Clipboard.setData(ClipboardData(text: _hexColor));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showAppSnackBar(const AppSnackBar(content: Text('颜色已复制')));
  }

  Future<void> _pasteColor() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final raw = (data?.text ?? '').trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(raw)) {
      ScaffoldMessenger.of(
        context,
      ).showAppSnackBar(const AppSnackBar(content: Text('请先复制颜色，例如 #246BCE')));
      return;
    }
    _change(HSVColor.fromColor(Color(0xff000000 | int.parse(raw, radix: 16))));
  }

  void _preview(int value) {
    if (widget.background) {
      LocalStore.instance.previewBackgroundColor(
        value,
        followSystem: _followSystem,
      );
    } else if (widget.button) {
      LocalStore.instance.previewButtonColor(value);
    } else {
      LocalStore.instance.previewThemeColor(value);
    }
  }

  void _change(HSVColor color, {bool dragging = false}) {
    setState(() {
      _color = color;
      _followSystem = false;
    });
    // Keep the active gesture independent of app-wide theme rebuilds.
    if (!dragging) _finishDrag();
  }

  void _finishDrag() {
    _preview(_color.toColor().toARGB32());
  }

  @override
  void dispose() {
    // Backing out of the preview leaves the saved theme unchanged.
    if (!_saved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _followSystem = _originalFollowsSystem;
        _preview(_original);
      });
    }
    super.dispose();
  }

  Future<void> _exactColor({bool hex = false}) async {
    final controller = TextEditingController(
      text: hex ? _hexColor : _color.hue.toStringAsFixed(1),
    );
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(hex ? '输入颜色代码' : '精确色相 · 0–360°'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: hex
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: hex ? '例如 #246BCE' : '色相（度）',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim().replaceFirst('#', '');
                final hue = double.tryParse(raw);
                final valid = hex
                    ? RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(raw)
                    : hue != null && hue.isFinite && hue >= 0 && hue <= 360;
                if (!valid) {
                  update(
                    () => error = hex
                        ? '请输入六位颜色代码，例如 #246BCE'
                        : '请输入 0–360 之间的数字',
                  );
                  return;
                }
                Navigator.pop(context, raw);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    // Dialog route may still be animating out; dispose after its transition.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (!mounted || value == null) return;
    _change(
      hex
          ? HSVColor.fromColor(Color(0xff000000 | int.parse(value, radix: 16)))
          : _color.withHue(double.parse(value) % 360),
    );
  }

  Future<void> _save() async {
    _finishDrag();
    setState(() => _saving = true);
    try {
      if (widget.background) {
        await LocalStore.instance.setBackgroundColor(
          _color.toColor().toARGB32(),
          followSystem: _followSystem,
        );
      } else if (widget.button) {
        await LocalStore.instance.setButtonColor(_color.toColor().toARGB32());
      } else {
        await LocalStore.instance.setThemeColor(_color.toColor().toARGB32());
      }
      _saved = true;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showAppSnackBar(const AppSnackBar(content: Text('颜色保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.background) {
      final store = LocalStore.instance;
      final background = Color(
        store.resolvedBackgroundColor(MediaQuery.platformBrightnessOf(context)),
      );
      // Preview the draft locally on every pointer move; keep the gesture's
      // widget tree stable and avoid rebuilding the whole app while dragging.
      return Theme(
        data: appTheme(
          widget.button ? Color(store.themeColor) : _color.toColor(),
          background.computeLuminance() <= .179
              ? Brightness.dark
              : Brightness.light,
          background: background,
          button: widget.button ? _color.toColor() : Color(store.buttonColor),
        ),
        child: Builder(builder: _buildPicker),
      );
    }

    final theme = Theme.of(context);
    final background = _followSystem
        ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
              ? Colors.black
              : Colors.white)
        : _color.toColor();
    final foreground = background.computeLuminance() > .179
        ? Colors.black
        : Colors.white;
    final buttonForeground = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled)
          ? foreground.withValues(alpha: .38)
          : foreground,
    );
    // Use the in-progress selection, including while a drag is active.
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: theme.colorScheme.copyWith(
          brightness: foreground == Colors.black
              ? Brightness.light
              : Brightness.dark,
          surface: background,
          onSurface: foreground,
          onSurfaceVariant: foreground,
          primary: foreground,
        ),
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: theme.iconTheme.copyWith(color: foreground),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: background,
          foregroundColor: foreground,
          actionsIconTheme: IconThemeData(color: foreground),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: buttonForeground,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                foregroundColor: buttonForeground,
                side: WidgetStatePropertyAll(
                  BorderSide(color: foreground.withValues(alpha: .5)),
                ),
              ),
        ),
      ),
      child: Builder(builder: _buildPicker),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final hue = HSVColor.fromAHSV(1, _color.hue, 1, 1).toColor();
    Widget slider(
      String label,
      double value,
      List<Color> colors,
      ValueChanged<double> onChanged,
    ) => Row(
      children: [
        SizedBox(width: 58, child: Text(label)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: _ColorGradientTrackShape(colors),
              thumbColor: _color.toColor(),
              overlayColor: _color.toColor().withValues(alpha: .12),
            ),
            child: Slider(
              value: value,
              onChanged: _saving ? null : onChanged,
              onChangeEnd: (_) => _finishDrag(),
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text('${(value * 100).round()}', textAlign: TextAlign.end),
        ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.background
                ? '背景颜色'
                : widget.button
                ? '按钮底色'
                : '强调色',
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中' : '保存'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(
                  constraints.maxWidth,
                  constraints.maxWidth * .62,
                );
                void pick(Offset point) {
                  if (_saving) return;
                  _change(
                    _color
                        .withSaturation((point.dx / size.width).clamp(0.0, 1.0))
                        .withValue(
                          (1 - point.dy / size.height).clamp(0.0, 1.0),
                        ),
                    dragging: true,
                  );
                }

                return Semantics(
                  label: '饱和度与明暗调色盘，也可使用下方滑块调整',
                  child: _ColorDragSurface(
                    onPick: pick,
                    onEnd: _finishDrag,
                    child: SizedBox.fromSize(
                      size: size,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.white, hue],
                                  ),
                                ),
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (_color.saturation * size.width - 9).clamp(
                              0.0,
                              size.width - 18,
                            ),
                            top: ((1 - _color.value) * size.height - 9).clamp(
                              0.0,
                              size.height - 18,
                            ),
                            child: IgnorePointer(
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Text('色相')),
                IconButton(
                  tooltip: '色相减一度',
                  onPressed: _saving
                      ? null
                      : () {
                          _change(_color.withHue((_color.hue - 1 + 360) % 360));
                        },
                  icon: const Icon(Icons.remove),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _exactColor(),
                  child: Text('${_color.hue.toStringAsFixed(1)}°'),
                ),
                IconButton(
                  tooltip: '色相加一度',
                  onPressed: _saving
                      ? null
                      : () {
                          _change(_color.withHue((_color.hue + 1) % 360));
                        },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : () => _exactColor(hex: true),
                  icon: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _color.toColor(),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  label: Text(_hexColor),
                ),
                TextButton(
                  onPressed: _saving ? null : _copyColor,
                  child: const Text('复制颜色'),
                ),
                TextButton(
                  onPressed: _saving ? null : _pasteColor,
                  child: const Text('粘贴颜色'),
                ),
              ],
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xffff0000),
                    Color(0xffffff00),
                    Color(0xff00ff00),
                    Color(0xff00ffff),
                    Color(0xff0000ff),
                    Color(0xffff00ff),
                    Color(0xffff0000),
                  ],
                ),
              ),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: hue,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: _color.hue / 360,
                  onChangeEnd: (_) => _finishDrag(),
                  onChanged: _saving
                      ? null
                      : (value) => _change(
                          _color.withHue(value * 360),
                          dragging: true,
                        ),
                ),
              ),
            ),
            slider('饱和度', _color.saturation, [
              _color.withSaturation(0).toColor(),
              _color.withSaturation(1).toColor(),
            ], (v) => _change(_color.withSaturation(v), dragging: true)),
            slider('明暗', _color.value, [
              _color.withValue(0).toColor(),
              _color.withValue(1).toColor(),
            ], (v) => _change(_color.withValue(v), dragging: true)),
            const SizedBox(height: 12),
            if (widget.background)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _saving
                          ? null
                          : () => _change(HSVColor.fromColor(Colors.white)),
                      child: const Text('白色'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: _saving
                          ? null
                          : () => _change(HSVColor.fromColor(Colors.black)),
                      child: const Text('黑色'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Semantics(
                      selected: _followSystem,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          backgroundColor: _followSystem
                              ? Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: .12)
                              : null,
                        ),
                        onPressed: _saving
                            ? null
                            : () {
                                setState(() => _followSystem = true);
                                _finishDrag();
                              },
                        child: const Text('根据系统切换'),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (!widget.background) const _AccentColorExamples(),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _change(
                      HSVColor.fromColor(
                        Color(widget.background ? 0xffF7F8FA : 0xff246BCE),
                      ),
                    ),
              child: Text(widget.background ? '恢复默认背景' : '恢复默认蓝色'),
            ),
          ],
        ),
      ),
    );
  }
}

// Paint along the actual thumb travel so each position shows its HSV color.
class _ColorGradientTrackShape extends RoundedRectSliderTrackShape {
  const _ColorGradientTrackShape(this.colors);

  final List<Color> colors;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final gradient = LinearGradient(
      colors: textDirection == TextDirection.rtl
          ? colors.reversed.toList()
          : colors,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..shader = gradient.createShader(rect),
    );
  }
}

class _AccentColorExamples extends StatelessWidget {
  const _AccentColorExamples();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('效果预览', style: text.titleSmall),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '推荐',
                      style: text.labelLarge?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '最新',
                      style: text.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const FeedIcon(
                      FeedGlyph.upvote,
                      filled: true,
                      size: 18,
                    ),
                    label: const Text('128'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: colors.outlineVariant),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('发布帖子'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('关注'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Claim touches immediately, so vertical drags cannot scroll the parent list.
class _ColorDragSurface extends StatefulWidget {
  const _ColorDragSurface({
    required this.onPick,
    required this.onEnd,
    required this.child,
  });
  final ValueChanged<Offset> onPick;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_ColorDragSurface> createState() => _ColorDragSurfaceState();
}

class _ColorDragSurfaceState extends State<_ColorDragSurface> {
  int? _pointer;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      EagerGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        widget.onPick(event.localPosition);
      },
      onPointerMove: (event) {
        if (_pointer == event.pointer) widget.onPick(event.localPosition);
      },
      onPointerUp: (event) {
        if (_pointer != event.pointer) return;
        widget.onPick(event.localPosition);
        _pointer = null;
        widget.onEnd();
      },
      onPointerCancel: (event) {
        if (_pointer != event.pointer) return;
        _pointer = null;
        widget.onEnd();
      },
      child: widget.child,
    ),
  );
}
