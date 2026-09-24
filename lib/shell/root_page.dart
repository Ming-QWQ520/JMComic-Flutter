import 'package:flutter/material.dart';

import '../pages/explore/category_page.dart';
import '../pages/home/home_page.dart';
import '../pages/search/search_page.dart';
import '../pages/user/profile_page.dart';

/// 根导航壳：首页 / 分类 / 搜索 / 我的。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 底部导航栏始终显示。此前“键盘弹起隐藏底栏”的 hack 依赖
    // MediaQuery.viewInsets，在部分机型（如 vivo edge-to-edge）上
    // 会残留幽灵 insets 导致底栏永久消失，表现为“底部导航栏无法
    // 正常显示”。键盘顶起的问题交由 Scaffold 默认行为处理即可。
    return Scaffold(
      body: IndexedStack(
        index: _index,
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
          onDestinationSelected: (int i) => setState(() => _index = i),
          backgroundColor: cs.surface,
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
