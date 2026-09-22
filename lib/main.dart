import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'pages/album_detail_page.dart';
import 'pages/home_page.dart' show WeekPage;
import 'pages/root_page.dart';
import 'pages/reader_page.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const JmComicApp());
}

/// JMComic-Flutter 应用根组件。
class JmComicApp extends StatelessWidget {
  const JmComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState state, _) {
          final light = ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7C5CFF),
              brightness: Brightness.light,
            ),
          );
          final dark = ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7C5CFF),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
          );
          return MaterialApp(
            title: 'JMComic-Flutter',
            theme: light,
            darkTheme: dark,
            themeMode: state.themeMode, // 默认跟随系统
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            onGenerateRoute: (RouteSettings settings) {
              switch (settings.name) {
                case '/album':
                  return MaterialPageRoute<void>(
                    builder: (_) => const AlbumDetailPage(),
                    settings: settings,
                  );
                case '/reader':
                  return MaterialPageRoute<void>(
                    builder: (_) => const ReaderPage(),
                    settings: settings,
                  );
                case '/week':
                  return MaterialPageRoute<void>(
                    builder: (_) => const WeekPage(),
                    settings: settings,
                  );
                default:
                  return MaterialPageRoute<void>(
                    builder: (_) => const RootPage(),
                    settings: settings,
                  );
              }
            },
          );
        },
      ),
    );
  }
}
