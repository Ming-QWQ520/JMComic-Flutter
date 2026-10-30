import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import 'github_service.dart';
import 'storage_service.dart';

/// 应用内更新服务：冷启动检测 + 选择下载通道（直链 / gh-proxy）+ 下载安装。
///
/// 需求：每次进入 APP 自动检测新版本，有更新时弹窗提示；弹窗与关于页
/// 均可选择「直链下载」或「gh-proxy 加速下载」。
class UpdateService {
  UpdateService._();

  /// 检测是否有新版本：有则返回最新 Release 信息；无更新或检测失败
  /// 返回 null（失败静默，不打扰用户）。
  static Future<ReleaseInfo?> checkForUpdate() async {
    final r = await GithubService.fetchLatestRelease();
    if (r == null || r.version.isEmpty) return null;
    if (!GithubService.isNewerVersion(r.version, kAppVersion)) return null;
    return r;
  }

  /// 纯函数：按设备 ABI 挑选最优 APK 下载地址（便于单测覆盖）。
  ///
  /// - arm64-v8a 设备 → arm64 专用包，缺失回退 universal；
  /// - armeabi-v7a 设备 → 32 位包（arm64 包不兼容），缺失回退 universal；
  /// - x86_64 设备 → x86_64 包，缺失回退 universal；
  /// - 其他/未知 → universal。
  static String pickApkUrl(ReleaseInfo r, String abi) {
    final urls = r.abiUrls;
    switch (abi) {
      case 'arm64-v8a':
        return urls['arm64-v8a'] ?? urls['universal'] ?? r.apkUrl;
      case 'armeabi-v7a':
        return urls['armeabi-v7a'] ?? urls['universal'] ?? r.apkUrl;
      case 'x86_64':
        return urls['x86_64'] ?? urls['universal'] ?? r.apkUrl;
      default:
        return urls['universal'] ?? r.apkUrl;
    }
  }

  /// 从下载地址推断架构标签（保存文件名用）。
  static String archOf(String url) {
    for (final arch in const <String>[
      'universal',
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ]) {
      if (url.contains(arch)) return arch;
    }
    return 'apk';
  }

  /// 按指定通道下载最新 APK（仅 Android；返回 null 表示失败）。
  ///
  /// [useProxy] = true 走 gh-proxy 前缀加速（失败自动回退直链）；
  /// false 为 GitHub 直链。
  static Future<File?> downloadApk({
    required ReleaseInfo release,
    required bool useProxy,
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final abi = await StorageService.getDeviceAbi();
    final url = pickApkUrl(release, abi);
    final arch = archOf(url);
    onStatus?.call('准备下载（$arch，${useProxy ? 'gh-proxy 加速' : '直链'}）…');
    final base = await getExternalStorageDirectory();
    // 关键修复沿用：必须用 updateDir.path 拼接保存路径，不能对
    // Directory 对象直接插值（其 toString() 是 "Directory: '...'"）。
    final updateDir = Directory('${base!.path}/update');
    await updateDir.create(recursive: true);
    final savePath =
        '${updateDir.path}/JMComic-Flutter-v${release.version}-$arch.apk';
    return GithubService.downloadUpdate(
      url: url,
      savePath: savePath,
      preferProxy: useProxy,
      onProgress: onProgress,
    );
  }

  /// 拉起系统安装器（仅 Android）。
  static Future<bool> installApk(File apk) => StorageService.installApk(apk.path);
}
