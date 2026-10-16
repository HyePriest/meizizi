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
    this.comment = false,
    this.iconOnly = false,
  });
  final String threadId, postId;
  final Json data;
  final bool comment;
  final bool iconOnly;
  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _busy = false, _liked = false, _uncertain = false;
  int _count = 0;
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
        (flag(agree['has_agree']) ||
            flag(widget.data['has_agree']) ||
            number(agree['agree_type']) == 2);
    _uncertain = flag(widget.data['_agree_uncertain']);
  }

  @override
  void didUpdateWidget(LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data && !_busy) _restore();
  }

  Future<void> _like() async {
    if (_busy || _uncertain) return;
    final auth = AuthStore.instance;
    if (!auth.isLoggedIn) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      // The reading page reloads after login; use the refreshed state on the next tap.
      return;
    }
    final identity = auth.activeId;
    setState(() => _busy = true);
    final api = TiebaApi();
    try {
      await api.agree(
        widget.threadId,
        postId: widget.postId,
        comment: widget.comment,
        undo: _liked,
      );
      if (!mounted || auth.activeId != identity) return;
      setState(() {
        _count = (_count + (_liked ? -1 : 1)).clamp(0, 2147483647);
        _liked = !_liked;
        // Keep the confirmed result in page-owned data when this lazy row is disposed.
        widget.data['agree'] = {
          ...object(widget.data['agree']),
          'agree_num': _count,
          'has_agree': _liked ? 1 : 0,
          'agree_type': _liked ? 2 : 0,
        };
        widget.data.remove('_agree_uncertain');
      });
    } catch (e) {
      if (mounted) {
        if (e is TiebaException && e.uncertain) {
          setState(() {
            _uncertain = true;
            widget.data['_agree_uncertain'] = 1;
          });
        }
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              e is TiebaException
                  ? (e.uncertain ? '点赞结果未确认，请刷新核对后再操作' : e.message)
                  : '点赞失败，请稍后重试',
            ),
          ),
        );
      }
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final label = _uncertain
        ? '请刷新核对'
        : (_count > 0 ? '$_count' : (_liked ? '已赞' : '赞'));
    return Tooltip(
      message: _uncertain ? label : '${_liked ? '已赞' : '赞'} $_count',
      child: TextButton(
        onPressed: _busy || _uncertain ? null : _like,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                      size: 18,
                    ),
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
