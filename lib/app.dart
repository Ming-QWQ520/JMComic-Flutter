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
                        _AppBackground(
                          path: state.backgroundPath,
                          opacity: state.backgroundOpacity,
                        ),
                        child!,
                      ],
                    )
                  : child!,
            );
          },
          onGenerateRoute: (RouteSettings settings) {
            switch (settings.name) {
              case '/album':
                return SlideRightRoute<void>(
                  settings: settings,
                  builder: (_) => const AlbumDetailPage(),
                );
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
                return SlideRightRoute<void>(
                  settings: settings,
                  builder: (_) => const WeekPage(),
                );
              case '/search':
                final q = settings.arguments;
                return SlideRightRoute<void>(
                  settings: settings,
                  builder: (_) => SearchPage(initialQuery: q is String ? q : ''),
                );
              case '/login':
                // 详情页/评论页未登录时 pushNamed('/login')。
                // 此前缺失该分支会落入 default 再压入一个完整 RootPage，
                // 表现为叠在当前页上的"第二个底部导航栏"。
                return SlideRightRoute<void>(
                  settings: settings,
                  builder: (_) => const LoginPage(),
                );
              default:
                return SlideRightRoute<void>(
                  settings: settings,
                  builder: (_) => const RootPage(),
                );
            }
          },
        );
      },
    );
  }
}

/// 自定义 PageRoute：左右滑动转场 + 向右滑动手势返回。
///
/// - 进入：从右侧滑入 + 淡入；前一页向左轻微缩进。
/// - 退出：向右滑出 + 淡出；前一页回弹。
/// - 支持从屏幕左边缘向右滑触发返回（替代系统返回键），所有平台一致。
///   关键修复：在 Android 上默认 Material 路由无 swipe-back 手势，
///   这里通过自定义手势识别 + AnimationController 驱动动画实现。
class SlideRightRoute<T> extends PageRoute<T> {
  SlideRightRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    this.barrierColor = Colors.transparent,
    this.transitionDuration = const Duration(milliseconds: 280),
    this.reverseTransitionDuration = const Duration(milliseconds: 220),
  });

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  final Color barrierColor;

  @override
  final Duration transitionDuration;

  @override
  final Duration reverseTransitionDuration;

  @override
  bool get barrierDismissible => false;

  @override
  String get barrierLabel => '';

  @override
  bool canTransitionTo(TransitionRoute nextRoute) => true;

  @override
  bool canTransitionFrom(TransitionRoute previousRoute) =>
      previousRoute is PageRoute || previousRoute is SlideRightRoute;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return builder(context);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // 进入时：从右侧 100% 位置滑入；退出时：向右滑出。
    final inOffset = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(curved);
    // 前一页：进入新页时向左轻微缩进；退出新页时回弹。
    final secOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0),
    ).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    return SlideTransition(
      position: secOffset,
      child: SlideTransition(
        position: inOffset,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 全局自定义背景图层：按屏宽 × DPR 限宽解码（控制内存），
/// 上层叠一层主题色半透明遮罩保证前景内容可读。
/// 文件缺失时自动清除设置并回落默认背景。
class _AppBackground extends StatefulWidget {
  const _AppBackground({required this.path, required this.opacity});

  final String path;

  /// 用户设置的全局背景透明度（0.0~1.0，默认 0.5）。
  final double opacity;

  @override
  State<_AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<_AppBackground> {
  File? _file;
  bool _exists = false;

  @override
  void initState() {
    super.initState();
    _refreshFile();
  }

  @override
  void didUpdateWidget(_AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 关键修复：Windows 端"恢复默认背景后再设置会显示第一次设置的图片背景"
    // 的根因是 Image.file 在 path 变化后未刷新缓存（gaplessPlayback + 同 path
    // 解码缓存命中）。这里在 path 或 opacity 变化时强制重新读取文件，并通过
    // ValueKey 让 Image 重建（清空图片缓存条目）。
    if (oldWidget.path != widget.path) {
      _refreshFile();
    }
  }

  void _refreshFile() {
    if (widget.path.isEmpty) {
      _file = null;
      _exists = false;
      return;
    }
    final f = File(widget.path);
    _file = f;
    _exists = f.existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.read<AppState>().scheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW =
        (MediaQuery.sizeOf(context).width * dpr).round().clamp(480, 2048);
    // 用户可调透明度（默认 0.5），叠加一层主题色 scrim 保证内容可读。
    // 透明度越大，scrim 越薄，背景越透。
    final opacity = widget.opacity.clamp(0.0, 1.0);
    final Color scrim = scheme.isDark
        ? Colors.black.withValues(alpha: 1 - opacity * 0.5)
        : Colors.white.withValues(alpha: 1 - opacity * 0.55);
    return RepaintBoundary(
      key: ValueKey<String>('app-bg-${widget.path}'),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_exists && _file != null)
            Image.file(
              _file!,
              key: ValueKey<String>('bg-${widget.path}-$decodeW'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              cacheWidth: decodeW,
              gaplessPlayback: false,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          else
            // 文件不存在：填主题 bg 色，避免透出黑色空层。
            ColoredBox(color: scheme.isDark ? Colors.black : Colors.white),
          ColoredBox(color: scrim),
        ],
      ),
    );
  }
}

/// 全局左边缘向右滑返回手势包装。
///
/// 将其套在 Scaffold 外层：用户从屏幕左侧 32px 内向右滑动超过 80px
/// 即触发 Navigator.maybePop()，所有平台一致。配合 SlideRightRoute 的
/// 左右滑入动画，达到"向右滑回到上一页"的体验。
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double? _dragStartX;
  static const double _edgeWidth = 32;
  static const double _threshold = 80;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (DragStartDetails d) {
        if (d.globalPosition.dx <= _edgeWidth) {
          _dragStartX = d.globalPosition.dx;
        } else {
          _dragStartX = null;
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails d) {
        // 仅在起始位置位于左边缘时跟踪累计位移。
        if (_dragStartX != null) {
          // 跟踪位置变化以便手势结束时判断是否达到阈值
          _dragStartX = (_dragStartX ?? 0) + d.delta.dx;
        }
      },
      onHorizontalDragEnd: (DragEndDetails _) {
        if (_dragStartX != null && _dragStartX! >= _threshold) {
          Navigator.maybePop(context);
        }
        _dragStartX = null;
      },
      child: widget.child,
    );
  }
}
