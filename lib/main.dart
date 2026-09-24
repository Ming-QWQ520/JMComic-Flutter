import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

void main() {
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
  runApp(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..init(),
      child: const JmComicApp(),
    ),
  );
}
