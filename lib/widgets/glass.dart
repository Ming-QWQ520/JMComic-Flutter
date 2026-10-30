import 'dart:ui';

import 'package:flutter/material.dart';

/// 毛玻璃（Glassmorphism）基础容器。
///
/// UI 重构统一入口：半透明渐变面板 + BackdropFilter 高斯模糊 +
/// 内侧高光描边，明暗主题自适应。构成与 [LiquidGlassPicker] 的
/// 弹层一致，供底栏 / 表单容器 / 信息卡等复用。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blur = 18,
    this.opacity,
    this.padding,
    this.enabled = true,
  });

  final Widget child;

  final BorderRadius borderRadius;

  /// 高斯模糊强度；[enabled] 为 false 时不挂 BackdropFilter
  /// （背后无内容可模糊时关闭，节省 GPU saveLayer 开销）。
  final double blur;

  /// 面板基础不透明度（默认明色 0.72 / 暗色 0.58）。
  final double? opacity;

  final EdgeInsetsGeometry? padding;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final bool dark = brightness == Brightness.dark;
    // 基础不透明度：明色玻璃白 0.72，暗色玻璃白 0.14；
    // [opacity] 为相对系数（1.0 = 默认），可整体加深/减淡。
    final double k = opacity ?? 1.0;
    final Color glassTop = dark
        ? Colors.white.withValues(alpha: (0.14 * k).clamp(0.0, 1.0))
        : Colors.white.withValues(alpha: (0.72 * k).clamp(0.0, 1.0));
    final Color glassBottom = dark
        ? Colors.white.withValues(alpha: (0.05 * k).clamp(0.0, 1.0))
        : Colors.white.withValues(alpha: (0.45 * k).clamp(0.0, 1.0));
    final Color borderColor = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);

    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[glassTop, glassBottom],
          stops: const <double>[0, 1],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          // 顶部内侧高光：玻璃上缘反光
          BoxShadow(
            color: dark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.65),
            blurRadius: 1,
            offset: const Offset(0, -0.6),
          ),
        ],
      ),
      child: child,
    );

    if (!enabled) return panel;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      ),
    );
  }
}

/// 毛玻璃底栏包装（底部导航栏等）。
///
/// [blur] 有可透内容（自定义背景 / 半透明前景）时才为 true，
/// 由调用方判断，避免在纯色底上白白跑 saveLayer。
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.child,
    required this.blur,
  });

  final Widget child;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    if (!blur) {
      return ClipRect(child: child);
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: child,
      ),
    );
  }
}
