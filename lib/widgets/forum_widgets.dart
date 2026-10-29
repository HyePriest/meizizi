import 'dart:async';

import 'reliable_image.dart';
import 'app_snack_bar.dart';

import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/local_store.dart';
import '../data/tieba_api.dart';
import '../pages/login_page.dart';

export '../data/models.dart' show forumName;

class ForumAvatar extends StatefulWidget {
  const ForumAvatar({super.key, required this.forum, this.size = 48});
  final Json forum;
  final double size;
  @override
  State<ForumAvatar> createState() => _ForumAvatarState();
}

class _ForumAvatarState extends State<ForumAvatar> {
  Future<Json>? _summary;
  Timer? _retry;
  int _attempts = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool force = false}) {
    final name = forumName(widget.forum);
    _summary = name.isEmpty ? null : TiebaApi.forumSummary(name, force: force);
  }

  @override
  void didUpdateWidget(covariant ForumAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (forumName(oldWidget.forum) != forumName(widget.forum)) {
      _retry?.cancel();
      _retry = null;
      _attempts = 0;
      _load();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direct = [
      widget.forum['avatar'],
      widget.forum['avatar_url'],
      widget.forum['image_url'],
    ].map(httpsImage).where((url) => url.isNotEmpty).toList();
    Widget picture(List<String> urls) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ReliableImage(
        urls: urls,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        fallback: SizedBox(
          width: widget.size,
          height: widget.size,
          child: const Icon(Icons.forum_outlined),
        ),
      ),
    );
    if (direct.isNotEmpty) return picture(direct);
    return FutureBuilder<Json>(
      future: _summary,
      builder: (_, snapshot) {
        final data = snapshot.data ?? <String, dynamic>{};
        final urls = [
          data['avatar'],
          data['avatar_url'],
          data['image_url'],
        ].map(httpsImage).where((url) => url.isNotEmpty).toList();
        if (urls.isEmpty &&
            snapshot.connectionState == ConnectionState.done &&
            _retry == null &&
            _attempts < 2) {
          _attempts++;
          _retry = Timer(const Duration(seconds: 2), () {
            if (!mounted) return;
            setState(() {
              _retry = null;
              _load(force: true);
            });
          });
        }
        return GestureDetector(
          onTap: urls.isEmpty
              ? () => setState(() {
                  _attempts = 0;
                  _retry?.cancel();
                  _retry = null;
                  _load(force: true);
                })
              : null,
          child: picture(urls),
        );
      },
    );
  }
}

class SignButton extends StatefulWidget {
  const SignButton({
    super.key,
    required this.name,
    this.signed = false,
    this.followed = true,
    this.compact = false,
    this.api,
    this.enabled = true,
    this.statusRevision = 0,
    this.onSigningChanged,
  });
  final String name;
  final bool signed;
  final bool followed;
  final bool compact;
  final TiebaApi? api;
  final bool enabled;
  final int statusRevision;
  final ValueChanged<bool>? onSigningChanged;
  @override
  State<SignButton> createState() => _SignButtonState();
}

class _SignButtonState extends State<SignButton> {
  bool _busy = false;
  String? _uncertainAccount;
  @override
  void didUpdateWidget(SignButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        (!_busy && oldWidget.statusRevision != widget.statusRevision)) {
      _uncertainAccount = null;
    }
  }

  Future<void> _sign() async {
    if (_busy || !widget.followed || !widget.enabled) return;
    final auth = AuthStore.instance;
    if (!auth.isLoggedIn) {
      final logged = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (logged != true || !mounted) return;
    }
    final identity = auth.bduss;
    setState(() => _busy = true);
    widget.onSigningChanged?.call(true);
    final api = widget.api ?? TiebaApi();
    try {
      final info = await api.signForum(widget.name);
      if (!mounted || auth.bduss != identity) return;
      await LocalStore.instance.markForumSigned(auth.activeId, widget.name);
      if (!mounted || auth.bduss != identity) return;
      ScaffoldMessenger.of(context).showAppSnackBar(
        AppSnackBar(
          content: Text(
            '签到成功 · 连续 ${info['cont_sign_num'] ?? info['sign_day_count'] ?? 1} 天 · 经验 +${info['sign_bonus_point'] ?? 0}',
          ),
        ),
      );
    } catch (e) {
      if (mounted && auth.bduss == identity) {
        if (e is TiebaException &&
            (e.message.contains('已签到') || e.message.contains('已经签到')) &&
            auth.bduss == identity) {
          await LocalStore.instance.markForumSigned(auth.activeId, widget.name);
          if (!mounted || auth.bduss != identity) return;
        }
        if (e is TiebaException && e.uncertain) {
          setState(() => _uncertainAccount = identity);
        }
        ScaffoldMessenger.of(context).showAppSnackBar(
          AppSnackBar(
            content: Text(
              e is TiebaException
                  ? (e.uncertain ? '签到结果未确认，请刷新吧页面核对后再操作' : e.message)
                  : '签到失败，请稍后再试',
            ),
          ),
        );
      }
    } finally {
      if (widget.api == null) api.close();
      if (mounted) {
        setState(() => _busy = false);
        if (auth.bduss == identity) widget.onSigningChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AuthStore.instance, LocalStore.instance]),
    builder: (context, _) {
      final auth = AuthStore.instance;
      final signed =
          auth.isLoggedIn &&
          (widget.signed ||
              LocalStore.instance.forumSigned(auth.activeId, widget.name));
      final uncertain = auth.isLoggedIn && _uncertainAccount == auth.bduss;
      if (widget.compact)
        return FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(72, 36),
          ),
          onPressed:
              _busy ||
                  signed ||
                  uncertain ||
                  !widget.followed ||
                  !widget.enabled
              ? null
              : _sign,
          child: Text(
            _busy
                ? '签到中'
                : signed
                ? '已签到'
                : uncertain
                ? '请刷新'
                : '签到',
          ),
        );
      return FilledButton.tonalIcon(
        onPressed:
            _busy || signed || uncertain || !widget.followed || !widget.enabled
            ? null
            : _sign,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(signed ? Icons.check : Icons.event_available),
        label: Text(
          _busy
              ? '签到中'
              : signed
              ? '已签到'
              : uncertain
              ? '请刷新核对'
              : widget.followed
              ? '签到'
              : '关注后签到',
        ),
      );
    },
  );
}
