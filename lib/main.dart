import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'pages/home_page.dart';

import 'data/auth_store.dart';
import 'data/local_store.dart';
import 'data/app_update.dart';
import 'data/theme_colors.dart';
import 'data/app_webview.dart';

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

class _TiebaAppState extends State<TiebaApp> {
  late int _backgroundColor;
  late bool _backgroundFollowsSystem;
  late int _themeColor;
  late int _buttonColor;
  @override
  void initState() {
    super.initState();
    _backgroundColor = LocalStore.instance.backgroundColor;
    _backgroundFollowsSystem = LocalStore.instance.backgroundFollowsSystem;
    _themeColor = LocalStore.instance.themeColor;
    _buttonColor = LocalStore.instance.buttonColor;
    LocalStore.instance.addListener(_changed);
    LocalStore.instance.appearanceRevision.addListener(_changed);
  }

  void _changed() {
    final background = LocalStore.instance.backgroundColor;
    final followSystem = LocalStore.instance.backgroundFollowsSystem;
    final color = LocalStore.instance.themeColor;
    final button = LocalStore.instance.buttonColor;
    if (_backgroundColor != background ||
        _backgroundFollowsSystem != followSystem ||
        _themeColor != color ||
        _buttonColor != button) {
      setState(() {
        _backgroundColor = background;
        _backgroundFollowsSystem = followSystem;
        _themeColor = color;
        _buttonColor = button;
      });
    }
  }

  @override
  void dispose() {
    LocalStore.instance.removeListener(_changed);
    LocalStore.instance.appearanceRevision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    themeMode: _backgroundFollowsSystem ? ThemeMode.system : ThemeMode.light,
    themeAnimationDuration: Duration.zero,
    title: '美滋滋',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(
      Color(_themeColor),
      !_backgroundFollowsSystem &&
              Color(_backgroundColor).computeLuminance() <= .179
          ? Brightness.dark
          : Brightness.light,
      background: Color(
        _backgroundFollowsSystem ? 0xffffffff : _backgroundColor,
      ),
      button: Color(_buttonColor),
    ),
    darkTheme: _backgroundFollowsSystem
        ? appTheme(
            Color(_themeColor),
            Brightness.dark,
            background: Colors.black,
            button: Color(_buttonColor),
          )
        : null,
    home: const HomePage(),
  );
}
