
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/local_store.dart';
import 'services/widget_bridge.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Android 15 (targetSdk 35+) 强制 edge-to-edge：显式启用并让 Scaffold
  // 通过 MediaQuery 正确为底部导航栏预留系统手势条空间，避免 NavigationBar
  // 与系统导航条重叠导致"底部导航栏显示异常"。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 启动期兜底样式：透明系统栏 + 深色图标（默认浅色主题下白色手势条/
  // 三键导航图标叠在白色底栏上会完全不可见）。运行期由 app.dart 中的
  // AnnotatedRegion 按当前主题亮度持续接管。
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  // 关键：在 runApp 之前预热 SharedPreferences——AppState 构造函数用
  // 同步读取（getStringSync 等）在首帧前恢复全部个性化设置（主题/背景/
  // 透明度等），否则首帧用默认样式、稍后跳变成保存样式。
  await LocalStore.instance.warmUp();
  // 配置 WidgetBridge：Native 通过 channel 触发跳转时，通过全局
  // navigatorKey 执行 pushNamed，避免依赖 BuildContext。
  // 导航器尚未就绪（冷启动早期）时跳转请求进入队列，
  // 由 app.dart 每帧尝试冲刷，保证快捷方式/组件跳转不丢。
  WidgetBridge.instance.configure(
    pushNamed: (String routeName, {Object? arguments}) async {
      final state = _navigatorKey.currentState;
      if (state != null) {
        state.pushNamed(routeName, arguments: arguments);
      } else {
        WidgetBridge.instance.enqueueRoute(routeName, arguments: arguments);
      }
    },
  );
  // 注入导航器就绪查询：app.dart 每帧冲刷队列时用。
  WidgetBridge.instance.setNavigatorReady(() => _navigatorKey.currentState);
  runApp(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..init(),
      child: const JmComicApp(),
    ),
  );
}

/// 全局 navigatorKey：让 WidgetBridge 在 Native 回调中也能执行路由跳转。
/// 由 JmComicApp 的 MaterialApp 关联，WidgetBridge 配置时已注入 pushNamed。
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'jm_root');

/// 供 app.dart 获取全局 navigatorKey 用。
GlobalKey<NavigatorState> get rootNavigatorKey => _navigatorKey;
