import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'pages/album/album_detail_page.dart';
import 'pages/home/week_page.dart';
import 'pages/reader/reader_page.dart';
import 'pages/search/search_page.dart';
import 'shell/root_page.dart';
import 'state/app_state.dart';

/// 应用根组件：主题 + 路由。
class JmComicApp extends StatelessWidget {
  const JmComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState state, _) {
        return MaterialApp(
          title: 'JMComic-Flutter',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: state.themeMode, // 默认跟随系统
          debugShowCheckedModeBanner: false,
          supportedLocales: const <Locale>[
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          onGenerateRoute: (RouteSettings settings) {
            switch (settings.name) {
              case '/album':
                return _fade<void>(const AlbumDetailPage(), settings);
              case '/reader':
                return MaterialPageRoute<void>(
                  builder: (_) => const ReaderPage(),
                  settings: settings,
                );
              case '/week':
                return _fade<void>(const WeekPage(), settings);
              case '/search':
                final q = settings.arguments;
                return _fade<void>(
                  SearchPage(initialQuery: q is String ? q : ''),
                  settings,
                );
              default:
                return _fade<void>(const RootPage(), settings);
            }
          },
        );
      },
    );
  }

  /// 页面转场：淡入 + 轻微上移。
  PageRouteBuilder<T> _fade<T>(Widget page, RouteSettings settings) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, Animation<double> a, _, Widget child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
