import 'package:flutter/material.dart';

import '../data/auth_store.dart';
import '../data/tieba_api.dart';
import '../pages/login_page.dart';

String forumName(Json forum) => firstText([forum['name'], forum['forum_name']]);

class ForumAvatar extends StatelessWidget {
  const ForumAvatar({super.key, required this.forum, this.size = 48});
  final Json forum;
  final double size;
  @override
  Widget build(BuildContext context) {
    final url = httpsImage(
      firstText([forum['avatar'], forum['avatar_url'], forum['image_url']]),
    );
    final fallback = SizedBox(
      width: size,
      height: size,
      child: const Icon(Icons.forum_outlined),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class SignButton extends StatefulWidget {
  const SignButton({super.key, required this.name, this.signed = false});
  final String name;
  final bool signed;
  @override
  State<SignButton> createState() => _SignButtonState();
}

class _SignButtonState extends State<SignButton> {
  bool _busy = false;
  String? _signedAccount;
  String? _uncertainAccount;
  @override
  void didUpdateWidget(SignButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _signedAccount = null;
      _uncertainAccount = null;
    }
  }

  Future<void> _sign() async {
    if (_busy) return;
    final auth = AuthStore.instance;
    if (!auth.isLoggedIn) {
      final logged = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
      if (logged != true || !mounted) return;
    }
    final identity = auth.bduss;
    setState(() => _busy = true);
    final api = TiebaApi();
    try {
      final info = await api.signForum(widget.name);
      if (!mounted || auth.bduss != identity) return;
      setState(() => _signedAccount = identity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '签到成功 · 连续 ${info['cont_sign_num'] ?? info['sign_day_count'] ?? 1} 天 · 经验 +${info['sign_bonus_point'] ?? 0}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        if (e is TiebaException && e.uncertain) {
          setState(() => _uncertainAccount = identity);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TiebaException
                  ? (e.uncertain ? '签到结果未确认，请刷新吧页面核对后再操作' : e.message)
                  : '签到失败，请稍后再试',
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthStore.instance,
    builder: (context, _) {
      final auth = AuthStore.instance;
      final signed =
          auth.isLoggedIn && (widget.signed || _signedAccount == auth.bduss);
      final uncertain = auth.isLoggedIn && _uncertainAccount == auth.bduss;
      return FilledButton.tonalIcon(
        onPressed: _busy || signed || uncertain ? null : _sign,
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
              : '签到',
        ),
      );
    },
  );
}
