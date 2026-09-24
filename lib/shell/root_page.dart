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
    // 键盘弹起时隐藏底部导航栏（对齐主流 App 行为）。Scaffold 默认会把
    // bottomNavigationBar 顶到键盘上方悬浮（viewInsets 补偿），导致搜索页
    // 可用区域被压扁、导航栏"悬空"在键盘上，表现为底部导航栏显示异常。
    final bool keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
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
      bottomNavigationBar: keyboardVisible
          ? null
          : Container(
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
