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
  /// Android：原生侧按可用性依次尝试系统选择器（resource/directory、
  /// vnd.android.document/directory 等意图），全部失败时退回系统
  /// "下载"管理器；返回 false 时由调用方提示路径文本兜底。
  /// Windows：直接调用 explorer.exe 定位到目录。
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
}
