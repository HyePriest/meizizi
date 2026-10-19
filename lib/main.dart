import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';

import 'data/auth_store.dart';
import 'data/local_store.dart';
import 'data/app_update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStore.instance.restore();
  await LocalStore.instance.restore();
  runApp(const TiebaApp());
  unawaited(AppUpdate.instance.check());
}

class TiebaApp extends StatefulWidget {
  const TiebaApp({super.key});
  @override
  State<TiebaApp> createState() => _TiebaAppState();
}

class _TiebaAppState extends State<TiebaApp> {
  late String _theme;
  @override
  void initState() {
    super.initState();
    _theme = LocalStore.instance.themePreference;
    LocalStore.instance.addListener(_changed);
  }

  void _changed() {
    final next = LocalStore.instance.themePreference;
    if (_theme != next) setState(() => _theme = next);
  }

  @override
  void dispose() {
    LocalStore.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    themeMode: switch (_theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    title: '贴吧',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff246BCE)),
      scaffoldBackgroundColor: const Color(0xffF7F8FA),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff246BCE),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}
