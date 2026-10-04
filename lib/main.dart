import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';

import 'data/auth_store.dart';
import 'data/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStore.instance.restore();
  await LocalStore.instance.restore();
  runApp(const TiebaApp());
}

class TiebaApp extends StatelessWidget {
  const TiebaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
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
