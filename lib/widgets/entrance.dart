import 'package:flutter/material.dart';

/// 首次构建入场动画：淡入 + 轻微上移。
///
/// 只在元素首次挂载时运行一次（TweenAnimationBuilder 无需控制器），
/// 列表滚动复用 Element 时不会重放，性能开销可忽略。
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// 入场延迟（用于分区/列表项的错峰编排）。
  final Duration delay;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final total = duration + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Curves.linear,
      builder: (BuildContext context, double t, Widget? w) {
        // 线性进度映射：delay 之后才进入 duration 区间，再做缓动。
        final raw = ((t * total.inMilliseconds - delay.inMilliseconds) /
                duration.inMilliseconds)
            .clamp(0.0, 1.0);
        final p = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, (1 - p) * 14),
            child: w,
          ),
        );
      },
      child: child,
    );
  }
}

/// 点击缩放反馈容器：按下时轻微缩小（0.97），松开回弹。
///
/// 仅驱动 Transform（不触发重排），适合卡片/封面等高频元素。
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
