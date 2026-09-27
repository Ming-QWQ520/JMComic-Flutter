import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

/// 应用锁门卫：包在 MaterialApp 外层的全屏锁定遮罩。
///
/// - 开启应用锁后：冷启动与从后台返回时先通过系统本地认证
///   （指纹/面容/锁屏密码）才能进入应用；
/// - 系统认证窗口弹出期间（[_authInFlight]）不重复上锁，避免认证
///   界面自身的生命周期变化造成"锁死循环"；认证失败后需手动重试；
/// - 遮罩位于 MaterialApp 之上（Stack 顶层），任何路由/弹窗都无法
///   绕过；自带 Directionality/Material，不依赖下层主题上下文。
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;

  /// 系统认证窗口是否正在弹出（期间生命周期变化不触发上锁/解锁）。
  bool _authInFlight = false;

  /// 上一次认证是否失败（失败后不再自动重弹，改为手动点按钮重试）。
  bool _failedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷启动：开启应用锁时直接进入锁定态并自动弹出认证。
    _locked = widget.enabled;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptUnlock();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    // 设置页开关应用锁（开启/关闭都已通过本地认证）。
    _locked = widget.enabled;
    _failedOnce = false;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptUnlock();
      });
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // 切后台/被遮挡（任务切换、通知栏下拉）即上锁；认证进行中
      // 除外——系统认证窗口会短暂改变生命周期，不能因此锁死。
      if (!_authInFlight) {
        _failedOnce = false;
        if (!_locked) setState(() => _locked = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_locked && !_failedOnce) _promptUnlock();
    }
  }

  Future<void> _promptUnlock() async {
    if (_authInFlight || !_locked) return;
    _authInFlight = true;
    final ok = await AppLockService.instance
        .authenticate('使用指纹、面容或锁屏密码解锁应用');
    _authInFlight = false;
    if (!mounted) return;
    setState(() {
      if (ok) {
        _locked = false;
        _failedOnce = false;
      } else {
        _failedOnce = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 关键：本组件包在 MaterialApp 之外，上方没有 Directionality 祖先。
    // Stack 默认 alignment 是 AlignmentDirectional.topStart，布局解析
    // 需要 Directionality，缺失会在根级 layout 直接崩溃
    //（"Null check operator used on a null value" @ RenderStack，
    // 表现为整个 App 卡死在启动画面，log.txt 已实锤）。
    // 因此这里显式提供 Directionality，并把 alignment 换成不依赖
    // 方向的 Alignment.topLeft 双保险。
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: <Widget>[
          widget.child,
          if (_locked)
            Positioned.fill(
              child: Material(
                color: const Color(0xFF101010),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.lock_rounded,
                          size: 56,
                          color: Color(0xFFFF8A00),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '应用已锁定',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _failedOnce ? '认证未通过，请重试' : '通过指纹、面容或锁屏密码解锁',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _authInFlight ? null : _promptUnlock,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8A00),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                          ),
                          icon: _authInFlight
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.fingerprint_rounded,
                                  size: 22),
                          label: Text(_authInFlight ? '等待认证…' : '解锁'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
