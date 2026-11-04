import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'data/app_update.dart';
import 'data/app_webview.dart';
import 'data/auth_store.dart';
import 'data/local_store.dart';
import 'data/theme_colors.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    MediaKit.ensureInitialized();
    try {
      await DesktopWebSession.initialize();
    } catch (error) {
      DesktopWebSession.initializationError = error;
    }
  }
  await Future.wait([
    AuthStore.instance.restore(),
    LocalStore.instance.restore(),
  ]);
  runApp(const TiebaApp());
  unawaited(AppUpdate.instance.check());
}

class TiebaApp extends StatefulWidget {
  const TiebaApp({super.key});
  @override
  State<TiebaApp> createState() => _TiebaAppState();
}

/// The saved colors that decide the app theme.
typedef _Appearance = ({
  int background,
  bool followSystem,
  int accent,
  int button,
});

_Appearance _savedAppearance() {
  final store = LocalStore.instance;
  return (
    background: store.backgroundColor,
    followSystem: store.backgroundFollowsSystem,
    accent: store.themeColor,
    button: store.buttonColor,
  );
}

class _TiebaAppState extends State<TiebaApp> {
  _Appearance _appearance = _savedAppearance();

  @override
  void initState() {
    super.initState();
    LocalStore.instance.addListener(_changed);
    LocalStore.instance.appearanceRevision.addListener(_changed);
  }

  // Rebuild the whole app only when a theme color actually changed.
  void _changed() {
    final next = _savedAppearance();
    if (next != _appearance) setState(() => _appearance = next);
  }

  @override
  void dispose() {
    LocalStore.instance.removeListener(_changed);
    LocalStore.instance.appearanceRevision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    themeMode: _appearance.followSystem ? ThemeMode.system : ThemeMode.light,
    themeAnimationDuration: Duration.zero,
    title: '美滋滋',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(
      Color(_appearance.accent),
      !_appearance.followSystem &&
              Color(_appearance.background).computeLuminance() <= .179
          ? Brightness.dark
          : Brightness.light,
      background: Color(
        _appearance.followSystem ? 0xffffffff : _appearance.background,
      ),
      button: Color(_appearance.button),
    ),
    darkTheme: _appearance.followSystem
        ? appTheme(
            Color(_appearance.accent),
            Brightness.dark,
            background: Colors.black,
            button: Color(_appearance.button),
          )
        : null,
    home: const HomePage(),
  );
}
