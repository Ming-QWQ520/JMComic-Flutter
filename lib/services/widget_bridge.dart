import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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

  /// 把一部随机推荐漫画同步到桌面小组件。
  Future<void> writeRandomAlbum({
    required String name,
    required String id,
    required String coverUrl,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('writeRandomAlbum', <String, dynamic>{
        'name': name,
        'id': id,
        'coverUrl': coverUrl,
      });
    } on PlatformException {
      // 静默失败
    }
  }
}
