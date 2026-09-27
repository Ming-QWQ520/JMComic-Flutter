import 'dart:io';

import 'package:flutter/services.dart';

/// 存储权限与系统文件夹打开（Android 原生通道）。
///
/// 下载位置默认为公共下载目录 `/storage/emulated/0/Download/JM-Flutter`，
/// 属于应用沙盒之外的公共目录：
/// - Android 10（API 29）：申请传统写权限 + `requestLegacyExternalStorage`；
/// - Android 11+（API 30+）：需要"所有文件访问"（MANAGE_EXTERNAL_STORAGE），
///   首次下载/设置中会跳转系统设置页引导用户授权；
/// - Android 9 及以下：运行时请求 WRITE/READ_EXTERNAL_STORAGE。
class StorageService {
  StorageService._();

  static const MethodChannel _channel = MethodChannel(
    'com.ming.jmcomic/storage',
  );

  static bool get isAndroid => Platform.isAndroid;

  /// 当前是否已具备存储权限。
  static Future<bool> hasStorage() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasStoragePermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 申请存储权限。
  ///
  /// - 已授权 → 直接返回 true；
  /// - 未授权：Android 11+ 跳转"所有文件访问"系统设置页（异步授权，
  ///   本次返回 false，用户授权返回后由调用方引导重新检查）；
  ///   Android 10 及以下弹出系统运行时权限对话框。
  static Future<bool> ensureStorage() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('ensureStoragePermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 调用系统文件管理器打开文件夹。
  ///
  /// Android：原生侧枚举能打开目录的管理器（SAF content:// + file://
  /// 各 MIME 形状），弹出应用内「打开方式」列表，点击后以显式意图
  /// 直接启动——不经过系统 ResolverActivity（vivo 等定制 ROM 会把
  /// 系统选择器静默改写为直开单个应用），任何 ROM 行为一致；列表
  /// 末尾附 SAF 目录选择器兜底。Windows：直接调用 explorer.exe。
  static Future<bool> openFolder(String path) async {
    if (path.isEmpty) return false;
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', <String>[path]);
        return true;
      } catch (_) {
        return false;
      }
    }
    if (!isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openFolder', <String, dynamic>{
            'path': path,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 用系统浏览器/外部应用打开链接。
  ///
  /// Android：ACTION_VIEW；Windows：cmd start（默认浏览器），
  /// 失败时回退 explorer。返回 false 表示无可用处理程序。
  static Future<bool> openUrl(String url) async {
    if (url.isEmpty) return false;
    if (Platform.isWindows) {
      try {
        await Process.run('cmd.exe', <String>['/c', 'start', '', url]);
        return true;
      } catch (_) {
        try {
          await Process.run('explorer.exe', <String>[url]);
          return true;
        } catch (_) {
          return false;
        }
      }
    }
    if (!isAndroid) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openUrl', <String, dynamic>{
            'url': url,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 调出系统分享面板（详情页分享按钮）。
  ///
  /// Android：ACTION_SEND 文本；Windows：复制到剪贴板并提示。
  static Future<void> shareText(String text, {String title = '分享'}) async {
    if (text.isEmpty) return;
    if (Platform.isWindows) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('shareText', <String, dynamic>{
        'text': text,
        'title': title,
      });
    } catch (_) {}
  }
}
