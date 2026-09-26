import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/explore/category_page.dart';
import '../pages/home/home_page.dart';
import '../pages/search/search_page.dart';
import '../pages/user/profile_page.dart';
import '../state/app_state.dart';

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
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _switchTo(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    // jumpToPage 不会触发 onPageChanged（避免 setState 双调用），
    // 故在此主动 setState 后再跳转。
    _pageController.jumpToPage(i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasBg = context.watch<AppState>().hasCustomBackground;
    // 底部导航栏始终显示。此前"键盘弹起隐藏底栏"的 hack 依赖
    // MediaQuery.viewInsets，在部分机型（如 vivo edge-to-edge）上
    // 会残留幽灵 insets 导致底栏永久消失，表现为"底部导航栏无法
    // 正常显示"。键盘顶起的问题交由 Scaffold 默认行为处理即可。
    return Scaffold(
      body: PageView(
        controller: _pageController,
        // 物理效果保持默认 PageScrollPhysics（带阻尼/回弹），
        // 桌面端 AppScrollBehavior 已把鼠标纳入 dragDevices。
        onPageChanged: (int i) => setState(() => _index = i),
        children: const <Widget>[
          HomePage(),
          CategoryPage(),
          SearchPage(),
          ProfilePage(),
        ],
      ),
      // Scaffold 会自动在 NavigationBar 下方垫 MediaQuery.viewPadding.bottom
      // （系统手势条高度），保证 edge-to-edge 下底栏不被遮挡。
      bottomNavigationBar: Container(
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
          // 自定义背景下底栏轻微透出背景图（保持可读性的半透明）。
          backgroundColor:
              hasBg ? cs.surface.withValues(alpha: 0.86) : cs.surface,
          surfaceTintColor: cs.surface,
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
    );
  }
}
