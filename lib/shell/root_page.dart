import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/explore/category_page.dart';
import '../pages/home/home_page.dart';
import '../pages/search/search_page.dart';
import '../pages/user/profile_page.dart';
import '../services/update_service.dart';
import '../services/widget_bridge.dart';
import '../state/app_state.dart';
import '../widgets/glass.dart';
import '../widgets/update_dialog.dart';

/// 根导航壳：首页 / 分类 / 搜索 / 我的。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;
  // 关键修复：此前用 IndexedStack 仅靠点击底栏切换，左右滑动无法切页。
  // 改为 PageView + PageController：左右滑动手势触发 onPageChanged → 同步
  // _index → 底栏高亮跟随。点击底栏 → _pageController.jumpToPage → 滚动
  // 到对应页 + setState 更新 _index。HomePage 的横滑 ListView 与
  // PageView 的横滑手势会进入 gesture arena 竞争：起点在 ListView 上
  // 时由 ListView 赢得（按分区滚动），起点在空白处由 PageView 赢得
  // （切换页面），符合常见 App 直觉。
  late final PageController _pageController =
      PageController(initialPage: _index);

  @override
  void initState() {
    super.initState();
    // 需求：每次进入 APP 自动检测是否有新版本，有则弹窗提示。
    // 延迟 1.6s 执行：避开首帧渲染与首页网络请求的争抢；
    // RootPage 是应用根路由，initState 每次冷启动恰好执行一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1600), _autoCheckUpdate);
    });
  }

  /// 自动检测更新：有新版本时弹出 [UpdateDialog]（失败静默不打扰）。
  Future<void> _autoCheckUpdate() async {
    if (!mounted) return;
    try {
      final update = await UpdateService.checkForUpdate();
      if (update == null || !mounted) return;
      await UpdateDialog.show(context, update);
    } catch (_) {
      // 检测失败静默：关于页仍有手动检测入口。
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchTo(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    // 物理仿真动画开启：animateToPage + easeOutBack 弹簧曲线（轻微过冲
    // 回弹，模拟弹簧阻尼）；关闭：保持原 jumpToPage（零动画开销）。
    final physicsOn = context.read<AppState>().anim.physicsAnimations;
    if (physicsOn) {
      _pageController
          .animateToPage(
            i,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
          )
          .catchError((_) {});
    } else {
      _pageController.jumpToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>();
    final hasBg = appState.hasCustomBackground;
    final cardOpacity = appState.cardOpacity;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 毛玻璃底栏（UI 重构）：底栏半透明白/暗面板；有自定义背景或前景
    // 半透明时背后有真实可透内容，启用 BackdropFilter 高斯模糊；
    // 纯色背景时只做半透明着色，不白跑 saveLayer。
    final bool glassBlur = hasBg || cardOpacity < 1.0;
    final Color navBarColor = dark
        ? Colors.white.withValues(alpha: glassBlur ? 0.10 : 1.0)
        : glassBlur
            ? Colors.white.withValues(alpha: 0.68)
            : cs.surface;
    // 物理仿真：底栏切换 PageView 用回弹滚动物理。
    final physicsOn = appState.anim.physicsAnimations;
    return Scaffold(
      body: PageView(
        controller: _pageController,
        // 物理仿真动画开启时使用 BouncingScrollPhysics（iOS 式阻尼回弹，
        // 全平台一致）；关闭时保持默认 Clamping 物理。
        physics: physicsOn
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics())
            : const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        onPageChanged: (int i) {
          setState(() => _index = i);
          // 同步给 Android 原生用于双击退出判断：根路由（index 任意
          // 都算根，因为 RootPage 自身就是根；非根路由由 push 进来
          // 的详情/阅读器页面占据）
          WidgetBridge.instance.isAtRoot = true;
        },
        children: const <Widget>[
          HomePage(),
          CategoryPage(),
          SearchPage(),
          ProfilePage(),
        ],
      ),
      // Scaffold 会自动在 NavigationBar 下方垫 MediaQuery.viewPadding.bottom
      // （系统手势条高度），保证 edge-to-edge 下底栏不被遮挡。
      // 毛玻璃底栏：GlassBottomBar 在有可透内容时挂 BackdropFilter。
      bottomNavigationBar: GlassBottomBar(
        blur: glassBlur,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.45),
                width: 0.6,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _switchTo,
            // 半透明玻璃底色（glassBlur 时配合高斯模糊成磨砂质感）。
            backgroundColor: navBarColor,
            surfaceTintColor: navBarColor,
            shadowColor: Colors.transparent,
            destinations: const <Widget>[
              NavigationDestination(
                icon: Icon(Icons.rocket_launch_outlined),
                selectedIcon: Icon(Icons.rocket_launch_rounded),
                label: '发现',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: '分类',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search_rounded),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
