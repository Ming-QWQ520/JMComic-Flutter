import 'package:flutter/material.dart';

/// Zoomable：自研缩放容器（双指捏合 / 双击缩放 / 缩放后单指平移）。
///
/// 为什么不用 InteractiveViewer：IV 的缩放手势识别器与外层 PageView /
/// ListView 的拖动手势在手势竞技场竞争，两指同向移动时拖动往往先越过
/// 阈值获胜，表现为"无法双指缩放"。本组件用 Listener 原始指针事件自行
/// 计算缩放（Listener 不参与竞技场），缩放只依赖双指间距变化，与父级
/// 手势互不干扰。
///
/// - 双指捏合：围绕手势起始的"内容锚点"缩放（1x..[maxScale]），
///   两指同向移动 = 平移，松手保持；
/// - 双击：围绕点击位置 1x ↔ 2.5x（回调 [onDoubleTapZoomed] 供外部联动）；
/// - 缩放后（>1.02x）单指拖动平移：内部 GestureDetector 接管，
///   父级翻页/滚动自动失效；回到 1x 后父级手势恢复；
/// - 双指捏回 1x 以下松手自动复位；
/// - 外部递增 [resetToken]（如翻页/换章）即可复位。
class Zoomable extends StatefulWidget {
  const Zoomable({
    super.key,
    required this.child,
    this.onPinchActive,
    this.onZoomChanged,
    this.onDoubleTapZoomed,
    this.resetToken = 0,
    this.maxScale = 4.0,
  });

  final Widget child;

  /// 双指触控期间回调 true（外部可临时禁用父级滚动），
  /// 双指全部抬起后回调 false。
  final ValueChanged<bool>? onPinchActive;

  /// 是否处于缩放态（scale > 1.02）：外部据此禁用父级翻页/滚动。
  final ValueChanged<bool>? onZoomChanged;

  /// 双击缩放后的状态回调（true=放大，false=复位）。
  final ValueChanged<bool>? onDoubleTapZoomed;

  /// 外部复位令牌：值变化即复位（翻页/换章时递增或直接换 key）。
  final int resetToken;

  final double maxScale;

  @override
  State<Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<Zoomable> {
  final Map<int, Offset> _pointers = <int, Offset>{};

  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // 手势起始快照（用于围绕锚点缩放）
  bool _pinching = false;
  double _scale0 = 1.0;
  double _span0 = 1.0;
  Offset _contentAnchor = Offset.zero;

  Offset _tapPos = Offset.zero;

  bool get _zoomed => _scale > 1.02;

  void _reset() {
    final wasZoomed = _zoomed;
    _scale = 1.0;
    _offset = Offset.zero;
    if (_pinching) {
      _pinching = false;
      widget.onPinchActive?.call(false);
    }
    if (wasZoomed) widget.onZoomChanged?.call(false);
    if (mounted) setState(() {});
  }

  void _applyZoom(double newScale, Offset newOffset) {
    final wasZoomed = _zoomed;
    _scale = newScale;
    _offset = newOffset;
    if (_zoomed != wasZoomed) widget.onZoomChanged?.call(_zoomed);
    if (mounted) setState(() {});
  }

  // ---------- 原始指针（双指缩放） ----------

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final ps = _pointers.values.toList();
      _pinching = true;
      widget.onPinchActive?.call(true);
      _span0 = (ps[0] - ps[1]).distance.clamp(1.0, double.infinity);
      _scale0 = _scale;
      final focal = (ps[0] + ps[1]) / 2;
      _contentAnchor = (focal - _offset) / _scale;
      if (mounted) setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pinching) return;
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length < 2) return;
    final ps = _pointers.values.toList();
    final span = (ps[0] - ps[1]).distance;
    final focal = (ps[0] + ps[1]) / 2;
    final s = (_scale0 * span / _span0).clamp(1.0, widget.maxScale);
    // 保持手势起始时两指中心下的内容点在指间：缩放 + 双指平移
    _applyZoom(s, focal - _contentAnchor * s);
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.isEmpty) {
      _pinching = false;
      widget.onPinchActive?.call(false);
      if (_scale < 1.05) {
        // 捏回约 1x：自动复位
        _applyZoom(1.0, Offset.zero);
      }
      if (mounted) setState(() {});
    }
  }

  // ---------- 双击缩放 ----------

  void _toggleDoubleTapZoom() {
    if (_zoomed) {
      _reset();
      widget.onDoubleTapZoomed?.call(false);
    } else {
      // 围绕双击位置放大：保持点击处的内容点不动
      final anchor = (_tapPos - _offset) / _scale;
      _applyZoom(2.5, _tapPos - anchor * 2.5);
      widget.onDoubleTapZoomed?.call(true);
    }
  }

  @override
  void didUpdateWidget(Zoomable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: GestureDetector(
        // 缩放后单指拖动 = 平移（1x 时不注册，父级翻页/滚动不受影响）
        onPanStart: _zoomed ? (DragStartDetails _) {} : null,
        onPanUpdate:
            _zoomed ? (DragUpdateDetails d) => _applyZoom(_scale, _offset + d.delta) : null,
        onDoubleTapDown: (TapDownDetails d) => _tapPos = d.localPosition,
        onDoubleTap: _toggleDoubleTapZoom,
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
              ..scaleByDouble(_scale, _scale, 1, 1),
            alignment: Alignment.topLeft,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
