import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// 应用锁：基于手机本地认证（指纹 / 面容 / 锁屏密码、图案）。
///
/// 走系统 BiometricPrompt（local_auth 3.x），`biometricOnly: false`
/// 允许在无生物识别或识别失败时回退到锁屏密码、图案——只要设备
/// 设置了安全锁屏即可启用应用锁。认证"正常失败"（用户取消/不匹配）
/// 返回 false；其余失败（设备未设置凭据等）会抛 LocalAuthException，
/// 这里统一捕获为 false，由调用方引导手动重试。
/// Windows 不启用（设置项仅在 Android 显示，本服务直接视为不支持）。
class AppLockService {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  final LocalAuthentication _auth = LocalAuthentication();

  bool get _isAndroid => Platform.isAndroid;

  /// 设备是否具备应用锁条件（已录入生物识别或设置了锁屏密码）。
  Future<bool> isDeviceSupported() async {
    if (!_isAndroid) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 弹出系统认证界面。返回 true = 认证通过。
  Future<bool> authenticate(String reason) async {
    if (!_isAndroid) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // BiometricPrompt 提示框文案（插件默认英文，这里中文化）
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: '身份验证',
            cancelButton: '取消',
          ),
        ],
        // 允许回退到锁屏密码/图案：纯生物识别失败时不至于无法进应用
        biometricOnly: false,
        // 认证过程切后台（来电等）后回前台自动继续，而不是直接判失败
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
