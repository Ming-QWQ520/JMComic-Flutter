import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/protocol/models.dart';
import '../state/app_state.dart';
import 'cover_image.dart';

/// 交互动效组件集（转场 / Hero / 物理仿真 / 3D 卡片统一入口）。
///
/// 四类动效均可在「设置 > 动画设置」独立开关；组件内部通过
/// `context.select` 只订阅对应开关位，开关切换外不会整页重建。
/// 默认只开启「页面转场 + Hero」（物理仿真与 3D 卡片默认关闭）。

/// 当前动画开关（供路由层等非组件环境读取；组件内请用 select）。
bool animTransitionsOn(BuildContext context) =>
    context.select<AppState, bool>((AppState s) => s.anim.pageTransitions);

/// 封面 Hero 联动（列表封面 → 详情页头图）。
///
/// [albumId] 同时作为 Hero tag 的一部分，保证列表端与详情端配对；
/// Hero 开关关闭时不包裹 Hero，直接返回 child。
class HeroCover extends StatelessWidget {
  const HeroCover({
    super.key,
    required this.albumId,
    required this.child,
  });

  /// JM 号（字符串形态：搜索列表条目为 String，详情页 Album 为 int，
  /// 调用方统一 toString 后传入）。
  final String albumId;
  final Widget child;

  static const String _prefix = 'album-cover-';

  /// 详情页端取同一个 tag（无论开关状态，tag 值规则一致）。
  static String tagOf(String albumId) => '$_prefix$albumId';

  @override
  Widget build(BuildContext context) {
    final heroOn = context.select<AppState, bool>(
      (AppState s) => s.anim.heroEnabled,
    );
    if (!heroOn) return child;
    return Hero(
      tag: tagOf(albumId),
      // 封面在列表端有圆角裁剪，详情端全幅无圆角：
      // flightShrinkWrap 由 Hero 自动处理，这里只关闭占位避免闪白。
      child: child,
    );
  }
}

/// 封面图（Hero 包裹版本）：列表卡片与详情页共用同一图像源，
/// 保证 Hero 飞行过程中内容视觉连续（同 URL 同解码缓存）。
class HeroAlbumCover extends StatelessWidget {
  const HeroAlbumCover({super.key, required this.album});

  final SearchAlbum album;

  @override
  Widget build(BuildContext context) {
    return HeroCover(
      albumId: album.id,
      child: CoverImage(album: album),
    );
  }
}

/// 3D 倾斜卡片：指针悬停（桌面）或按压拖动（触摸）时按指针相对
/// 位置做透视旋转，营造立体卡片观感。
///
/// - 仅在「设置 > 动画设置 > 3D 卡片动画」开启时生效，关闭时直接
///   返回原 child（零额外开销）；
/// - 只驱动 Transform（Matrix4 perspective rotate），不触发重排；
/// - 最大倾角 8°，阻尼跟随（AnimatedMatrix4 等效：手动 lerp），松手回弹。
class Tilt3DCard extends StatefulWidget {
  const Tilt3DCard({
    super.key,
    required this.child,
    this.maxTilt = 0.14,
  });

  final Widget child;

  /// 最大倾角（弧度），0.14 ≈ 8°。
  final double maxTilt;

  @override
  State<Tilt3DCard> createState() => _Tilt3DCardState();
}

class _Tilt3DCardState extends State<Tilt3DCard> {
  Offset _pos = Offset.zero; // -1..1 归一化指针位置
  bool _active = false;

  /// 根据指针全局坐标更新归一化位置。
  void _update(PointerEvent e, {required bool active}) {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(e.position);
    setState(() {
      _active = active;
      _pos = active
          ? Offset(
              ((local.dx / box.size.width) * 2 - 1).clamp(-1.0, 1.0),
              ((local.dy / box.size.height) * 2 - 1).clamp(-1.0, 1.0),
            )
          : Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppState, bool>(
      (AppState s) => s.anim.card3d,
    );
    if (!enabled) return widget.child;
    return MouseRegion(
      onHover: (PointerHoverEvent e) => _update(e, active: true),
      onExit: (PointerExitEvent e) => _update(e, active: false),
      child: Listener(
        onPointerDown: (PointerDownEvent e) => _update(e, active: true),
        onPointerUp: (PointerUpEvent e) => _update(e, active: false),
        onPointerCancel: (PointerCancelEvent e) => _update(e, active: false),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween<Offset>(end: _pos),
          duration: Duration(milliseconds: _active ? 90 : 320),
          curve: _active ? Curves.easeOut : Curves.elasticOut,
          builder: (BuildContext c, Offset p, Widget? w) {
            final double tiltX = _active ? p.dy * widget.maxTilt : 0.0;
            final double tiltY = _active ? -p.dx * widget.maxTilt : 0.0;
            final Matrix4 m = Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // 透视深度
              ..rotateX(tiltX)
              ..rotateY(tiltY);
            return Transform(
                transform: m, alignment: Alignment.center, child: w);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// 弹簧曲线（物理仿真开关开启时的交互回弹曲线）。
///
/// 开启物理仿真：交互返回 elasticOut（轻微过冲回弹，弹簧仿真观感）；
/// 关闭：标准 easeOut。
Curve springCurve(BuildContext context) {
  final physicsOn = context.select<AppState, bool>(
    (AppState s) => s.anim.physicsAnimations,
  );
  return physicsOn ? Curves.easeOutBack : Curves.easeOut;
}
