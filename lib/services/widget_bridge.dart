import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show NavigatorState;

import '../core/protocol/jm_api.dart';

/// 桌面小组件 + 长按图标快捷菜单的数据桥（Android 原生 MethodChannel）。
///
/// 双向通信：
/// - Flutter → Native：writeUserName / writeRandomAlbum 把登录态/随机推荐
///   数据写入 SharedPreferences，触发 widget 刷新。
/// - Native → Flutter：长按图标 shortcut 或桌面小组件点击跳转时，
///   Android 通过 channel.invokeMethod("jm_action", {action, albumId})
///   把动作发到 Flutter，由 [WidgetBridge._onAction] 处理导航。
///
/// 同时 main 端监听 channel 的 isAtRoot 方法调用，告诉原生是否在根路由
/// （决定双击退出逻辑是否启用）。
class WidgetBridge {
  WidgetBridge._();

  static final WidgetBridge instance = WidgetBridge._();

  static const MethodChannel _channel = MethodChannel('com.ming.jmcomic/widget');

  /// 当前是否处于根路由（用于 Android 双击退出）。
  /// 由 RootPage 的 PageController 在 onPageChanged 时同步。
  bool isAtRoot = true;

  /// action → 回调表：外部注册 shortcut / widget 点击的处理逻辑。
  /// 默认实现：random → /album 路由 pushNamed(albumId)；weekly → /week；
  /// user → /login 或不做特殊处理（已经在根路由）。
  final Map<String, Future<void> Function(String? albumId)> _handlers =
      <String, Future<void> Function(String?)>{};

  /// 全局 BuildContext 上下文（由 app.dart 注入），用于路由跳转。
  /// 设为 nullable 以避免 BuildContext 跨异步持有。
  Future<void> Function(String routeName, {Object? arguments})?
      _pushNamed;

  void configure({
    required Future<void> Function(String routeName, {Object? arguments})
        pushNamed,
  }) {
    _pushNamed = pushNamed;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// 注册特定 action 的处理回调（用于自定义导航）。
  void registerAction(String action,
      Future<void> Function(String? albumId) handler) {
    _handlers[action] = handler;
  }

  // ---------- 冷启动路由队列 ----------
  //
  // Native 的 jm_action 在引擎启动后 ~400ms 就可能到达，而此时
  // MaterialApp/Navigator 未必构建完成（currentState == null），
  // 直接 pushNamed 会被静默吞掉——表现为"快捷方式进入首页"。
  // 跳转请求先进队列，由 app.dart 每帧调用 flushPendingRoutes 冲刷。

  final List<Map<String, Object?>> _pendingRoutes = <Map<String, Object?>>[];

  /// 导航器未就绪时暂存跳转请求。
  void enqueueRoute(String routeName, {Object? arguments}) {
    _pendingRoutes.add(<String, Object?>{
      'route': routeName,
      'arguments': arguments,
    });
  }

  /// 导航器就绪后冲刷队列（app.dart 每帧调用，队列为空时零开销）。
  void flushPendingRoutes() {
    if (_pendingRoutes.isEmpty) return;
    final state = _navigatorReady?.call();
    if (state == null) return;
    for (final r in _pendingRoutes) {
      state.pushNamed(
        r['route']! as String,
        arguments: r['arguments'],
      );
    }
    _pendingRoutes.clear();
  }

  /// 由 configure 注入的"当前导航器状态"查询（可为 null = 未配置）。
  NavigatorState? Function()? _navigatorReady;

  /// configure 时注入导航器查询。
  void setNavigatorReady(NavigatorState? Function() ready) {
    _navigatorReady = ready;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'jm_action':
        // Native 通过 shortcut / widget 点击触发，参数 {action, albumId}
        final args = (call.arguments as Map?)?.cast<String, dynamic>();
        final action = args?['action'] as String? ?? '';
        final albumId = args?['albumId'] as String?;
        final isEmptyAlbumId =
            (albumId == null || albumId.isEmpty || albumId == 'null');
        await _dispatchAction(action, isEmptyAlbumId ? null : albumId);
        return null;
      case 'isAtRoot':
        // Native onBackPressed 询问 Flutter 是否在根路由
        return isAtRoot;
      default:
        return null;
    }
  }

  Future<void> _dispatchAction(String action, String? albumId) async {
    final handler = _handlers[action];
    if (handler != null) {
      await handler(albumId);
      return;
    }
    // 默认处理
    switch (action) {
      case 'random':
        if (albumId != null && albumId.isNotEmpty) {
          await _pushNamed?.call('/album', arguments: albumId);
        } else {
          // 快捷方式「随机推荐一部」不带 album_id（静态 XML 无法携带）：
          // 现场拉取随机推荐并打开第一部。
          try {
            final list = await JmApi.instance.getRandomRecommend();
            if (list.isNotEmpty) {
              await _pushNamed?.call('/album', arguments: list.first.id);
            }
          } catch (_) {}
        }
        break;
      case 'weekly':
        await _pushNamed?.call('/week');
        break;
      case 'user':
        // 用户页：默认在根路由即可，不做特殊跳转
        break;
      default:
        break;
    }
  }

  /// 把当前登录用户名同步到桌面小组件（登录/退出时调用）。
  Future<void> writeUserName(String? name) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('writeUserName', <String, dynamic>{
        'name': name ?? '未登录',
      });
    } on PlatformException {
      // 静默失败：widget 不应阻塞主流程
    }
  }

  /// 把一批随机推荐漫画同步到桌面小组件（多页轮播展示）。
  ///
  /// [albums] 每项含 name / id / coverUrl；widget 端按 ViewFlipper
  /// 多页渲染，左右翻页按钮 + 页码指示，点击某页打开对应详情。
  Future<void> writeRandomAlbums(
    List<Map<String, String>> albums,
  ) async {
    if (!Platform.isAndroid || albums.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('writeRandomAlbums', <String, dynamic>{
        'albums': albums,
      });
    } on PlatformException {
      // 静默失败：widget 不应阻塞主流程
    }
  }
}
