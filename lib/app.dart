import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

/// 全局滚动行为：桌面端（Windows）默认只有触摸才能拖拽列表，
/// 鼠标按住首页横滑分区/漫画网格拖不动。这里把鼠标/触控笔/触控板
/// 全部纳入 dragDevices，桌面端体验与触摸一致；触摸端不受影响。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      };
}

/// 应用根组件：主题 + 路由 + 全局自定义背景。
class JmComicApp extends StatelessWidget {
  const JmComicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState state, _) {
        final scheme = state.scheme;
        final hasBg = state.hasCustomBackground;
        return MaterialApp(
          title: 'JMComic-Flutter',
          theme: AppTheme.light(scheme, hasBg),
          darkTheme: AppTheme.dark(scheme, hasBg),
          themeMode: scheme.isDark ? ThemeMode.dark : ThemeMode.light,
          debugShowCheckedModeBanner: false,
          scrollBehavior: const AppScrollBehavior(),
          // 关键修复：必须显式提供本地化委托。此前未配置，新版本 Flutter
          // 不再自动注入 Material 本地化，导致 TextField/BackButton/Slider
          // 等组件首次构建时 MaterialLocalizations.of 直接空指针崩溃，
          // 表现为搜索框/返回键渲染成纯色方块且无法交互（log.txt 已实锤）。
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          locale: const Locale('zh', 'CN'),
          // 系统栏样式随主题亮度切换：浅色主题用深色图标、深色主题用浅色
          // 图标。edge-to-edge 下系统手势条/三键导航直接叠在应用底栏上，
          // 若图标亮度与底栏背景不匹配会导致"底部导航栏不可见"。
          builder: (BuildContext context, Widget? child) {
            final Brightness iconBrightness = scheme.isDark
                ? Brightness.light
                : Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: iconBrightness,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              // 自定义背景：垫在 Navigator 之下，全页面透出
              // （阅读器自设黑色 Scaffold 背景，天然不受影响）。
              child: hasBg
                  ? Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _AppBackground(path: state.backgroundPath),
                        child!,
                      ],
                    )
                  : child!,
            );
          },
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

/// 全局自定义背景图层：按屏宽 × DPR 限宽解码（控制内存），
/// 上层叠一层主题色半透明遮罩保证前景内容可读。
/// 文件缺失时自动清除设置并回落默认背景。
class _AppBackground extends StatefulWidget {
  const _AppBackground({required this.path});

  final String path;

  @override
  State<_AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<_AppBackground> {
  @override
  Widget build(BuildContext context) {
    final scheme = context.read<AppState>().scheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW =
        (MediaQuery.sizeOf(context).width * dpr).round().clamp(480, 2048);
    final Color scrim = scheme.isDark
        ? Colors.black.withValues(alpha: 0.52)
        : Colors.white.withValues(alpha: 0.58);
    final f = File(widget.path);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (f.existsSync())
            Image.file(
              f,
              key: ValueKey<String>('bg-${widget.path}'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              cacheWidth: decodeW,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ColoredBox(color: scrim),
        ],
      ),
    );
  }
}
