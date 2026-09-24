import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'pages/album/album_detail_page.dart';
import 'pages/download/local_reader_page.dart';
import 'pages/home/week_page.dart';
import 'pages/reader/reader_page.dart';
import 'pages/search/search_page.dart';
import 'pages/user/login_page.dart';
import 'shell/root_page.dart';
import 'state/app_state.dart';

/// 应用根组件：主题 + 路由。
class JmComicApp extends StatelessWidget {
  const JmComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState state, _) {
        final scheme = state.scheme;
        return MaterialApp(
          title: 'JMComic-Flutter',
          theme: AppTheme.light(scheme),
          darkTheme: AppTheme.dark(scheme),
          themeMode: scheme.isDark ? ThemeMode.dark : ThemeMode.light,
          debugShowCheckedModeBanner: false,
          // 系统栏样式随主题亮度切换：浅色主题用深色图标、深色主题用浅色
          // 图标。edge-to-edge 下系统手势条/三键导航直接叠在应用底栏上，
          // 若图标亮度与底栏背景不匹配会导致"底部导航栏不可见"。
          builder: (BuildContext context, Widget? child) {
            final Brightness iconBrightness =
                scheme.isDark ? Brightness.light : Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: iconBrightness,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              child: child!,
            );
          },
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
              case '/local_reader':
                return MaterialPageRoute<void>(
                  builder: (_) => const LocalReaderPage(),
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
              case '/login':
                // 详情页/评论页未登录时 pushNamed('/login')。
                // 此前缺失该分支会落入 default 再压入一个完整 RootPage，
                // 表现为叠在当前页上的“第二个底部导航栏”。
                return _fade<void>(const LoginPage(), settings);
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
