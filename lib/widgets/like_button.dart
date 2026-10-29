import 'dart:async';

import 'app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../pages/login_page.dart';
import 'feed_icons.dart';
import 'thread_feed_action_style.dart';

class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.threadId,
    required this.data,
    this.postId = '0',
    this.parentPostId,
    this.comment = false,
    this.iconOnly = false,
    this.feedStyle = false,
    this.feedColors = false,
    this.iconSize,
    this.onChanged,
  });
  final String threadId, postId;
  final String? parentPostId;
  final Json data;
  final bool comment;
  final bool iconOnly;
  final bool feedStyle;
  final bool feedColors;
  final double? iconSize;
  final void Function(Json source, Json patch)? onChanged;
  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => _busy;
  bool _busy = false, _liked = false, _uncertain = false;
  int _count = 0;
  bool _confirmedLiked = false;
  int _confirmedCount = 0;
  bool _countIncreasing = true;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _restore([Json? source]) {
    final data = source ?? widget.data;
    final agree = object(data['agree']);
    _count = number(agree['agree_num'] ?? data['agree_num'] ?? data['zan_num']);
    _liked =
        AuthStore.instance.isLoggedIn &&
        (agree.containsKey('has_agree')
            ? flag(agree['has_agree'])
            : agree.containsKey('agree_type')
            ? number(agree['agree_type']) == 2
            : flag(data['has_agree']));
    _confirmedLiked = _liked;
    _confirmedCount = _count;
    _uncertain = flag(data['_agree_uncertain']);
  }

  @override
  void didUpdateWidget(LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data && !_busy) _restore();
  }

  Future<void> _like() async {
    if (_uncertain) {
      if (!_busy) await _recover();
      return;
    }
    final auth = AuthStore.instance;
    if (!auth.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      // The reading page reloads after login; use the refreshed state on the next tap.
      return;
    }
    final identity = auth.activeId;
    setState(() {
      _liked = !_liked;
      _updateCount();
    });
    // Keep the last tap as the desired state, with only one request in flight.
    if (_busy) return;
    setState(() => _busy = true);
    final api = TiebaApi();
    updateKeepAlive();
    try {
      while (mounted && auth.activeId == identity) {
        // Coalesce rapid taps before sending another server operation.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted ||
            auth.activeId != identity ||
            _liked == _confirmedLiked) {
          break;
        }
        final desired = _liked;
        await api.agree(
          widget.threadId,
          postId: widget.postId,
          comment: widget.comment,
          undo: !desired,
        );
        if (!mounted || auth.activeId != identity) return;
        setState(() {
          _confirmedCount = (_confirmedCount + (desired ? 1 : -1)).clamp(
            0,
            2147483647,
          );
          _confirmedLiked = desired;
          _storeConfirmed();
          _updateCount();
        });
      }
    } catch (e) {
      if (mounted && auth.activeId == identity) {
        setState(() {
          _liked = _confirmedLiked;
          _count = _confirmedCount;
          // A rejected operation can also mean our local state was stale.
          // Reconcile before allowing another write instead of repeating it.
          _uncertain = true;
          _write({'_agree_uncertain': 1});
        });
        if (e is! TiebaException || !e.uncertain) {
          ScaffoldMessenger.of(context).showAppSnackBar(
            AppSnackBar(
              content: Text(e is TiebaException ? e.message : '点赞失败，请稍后重试'),
            ),
          );
        }
        await _readState(api, identity);
      }
    } finally {
      api.close();
      if (mounted) {
        setState(() => _busy = false);
        updateKeepAlive();
      }
    }
  }

  void _updateCount() {
    final previous = _count;
    _count =
        (_confirmedCount + (_liked == _confirmedLiked ? 0 : (_liked ? 1 : -1)))
            .clamp(0, 2147483647);
    if (_count != previous) _countIncreasing = _count > previous;
  }

  void _storeConfirmed() {
    _write({
      'agree': {
        ...object(widget.data['agree']),
        'agree_num': _confirmedCount,
        'has_agree': _confirmedLiked ? 1 : 0,
        'agree_type': _confirmedLiked ? 2 : 0,
      },
      'has_agree': _confirmedLiked ? 1 : 0,
      '_agree_uncertain': 0,
    });
  }

  void _write(Json patch) {
    final onChanged = widget.onChanged;
    if (onChanged != null) {
      onChanged(widget.data, patch);
    } else {
      // Older screens migrate independently; they still own mutable API maps.
      widget.data.addAll(patch);
    }
  }

  Future<void> _readState(TiebaApi api, String identity) async {
    try {
      final agree = await api.agreeState(
        widget.threadId,
        postId: widget.postId,
        comment: widget.comment,
        parentPostId: widget.parentPostId,
      );
      if (!mounted || AuthStore.instance.activeId != identity) return;
      setState(() {
        final patch = <String, dynamic>{'agree': agree, '_agree_uncertain': 0};
        final resolved = {...widget.data, ...patch};
        _write(patch);
        _restore(resolved);
      });
    } catch (_) {
      if (!mounted || AuthStore.instance.activeId != identity) return;
      ScaffoldMessenger.of(context).showAppSnackBar(
        const AppSnackBar(content: Text('点赞状态暂未确认，点击点赞按钮可重新同步')),
      );
    }
  }

  Future<void> _recover() async {
    setState(() => _busy = true);
    updateKeepAlive();
    final api = TiebaApi();
    try {
      await _readState(api, AuthStore.instance.activeId);
    } finally {
      api.close();
      if (mounted) {
        setState(() => _busy = false);
        updateKeepAlive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final label = _uncertain
        ? '点击同步'
        : (_count > 0 ? '$_count' : (_liked ? '已赞' : '赞'));
    return Tooltip(
      message: _uncertain ? label : '${_liked ? '已赞' : '赞'} $_count',
      child: TextButton(
        onPressed: _like,
        style: TextButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
          overlayColor: Colors.transparent,
          foregroundColor: widget.feedStyle || widget.feedColors
              ? ThreadFeedActionStyle.color(context, liked: _liked)
              : _liked
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: widget.feedStyle
                    ? ThreadFeedActionStyle.iconSize / (widget.iconSize ?? 22)
                    : 1,
                child: IconTheme(
                  data: IconThemeData(
                    color: widget.feedStyle || widget.feedColors
                        ? ThreadFeedActionStyle.color(context, liked: _liked)
                        : IconTheme.of(context).color,
                  ),
                  child: FeedIcon(
                    FeedGlyph.upvote,
                    filled: _liked,
                    size: widget.iconSize ?? (widget.feedStyle ? 22 : 18),
                  ),
                ),
              ),
              ...[
                const SizedBox(width: 4),
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final incoming = child.key == ValueKey(_count);
                      final direction = _countIncreasing ? 1.0 : -1.0;
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0, incoming ? direction : -direction),
                          end: Offset.zero,
                        ).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: Transform.scale(
                      key: ValueKey(_count),
                      scale: widget.feedStyle
                          ? ThreadFeedActionStyle.numberScale
                          : 1,
                      child: Text(
                        widget.feedStyle &&
                                object(widget.data['agree'])['agree_num'] ==
                                    null &&
                                widget.data['agree_num'] == null &&
                                widget.data['zan_num'] == null
                            ? '—'
                            : '$_count',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
