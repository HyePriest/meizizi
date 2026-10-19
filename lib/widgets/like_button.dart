import 'dart:async';

import 'app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../pages/login_page.dart';

class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.threadId,
    required this.data,
    this.postId = '0',
    this.parentPostId,
    this.comment = false,
    this.iconOnly = false,
  });
  final String threadId, postId;
  final String? parentPostId;
  final Json data;
  final bool comment;
  final bool iconOnly;
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
  @override
  void initState() {
    super.initState();
    _restore();
  }

  void _restore() {
    final agree = object(widget.data['agree']);
    _count = number(
      agree['agree_num'] ?? widget.data['agree_num'] ?? widget.data['zan_num'],
    );
    _liked =
        AuthStore.instance.isLoggedIn &&
        (agree.containsKey('has_agree')
            ? flag(agree['has_agree'])
            : agree.containsKey('agree_type')
            ? number(agree['agree_type']) == 2
            : flag(widget.data['has_agree']));
    _confirmedLiked = _liked;
    _confirmedCount = _count;
    _uncertain = flag(widget.data['_agree_uncertain']);
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
          widget.data['_agree_uncertain'] = 1;
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
    _count =
        (_confirmedCount + (_liked == _confirmedLiked ? 0 : (_liked ? 1 : -1)))
            .clamp(0, 2147483647);
  }

  void _storeConfirmed() {
    widget.data['agree'] = {
      ...object(widget.data['agree']),
      'agree_num': _confirmedCount,
      'has_agree': _confirmedLiked ? 1 : 0,
      'agree_type': _confirmedLiked ? 2 : 0,
    };
    widget.data['has_agree'] = _confirmedLiked ? 1 : 0;
    widget.data.remove('_agree_uncertain');
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
        widget.data['agree'] = agree;
        widget.data.remove('_agree_uncertain');
        _restore();
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
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_liked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18),
              if (!widget.iconOnly || _count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  widget.iconOnly ? '$_count' : label,
                  maxLines: 1,
                  softWrap: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
