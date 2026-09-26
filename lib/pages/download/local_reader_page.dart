import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';

/// 本地离线阅读器（对齐 qt local_read_view）。
///
/// 直接展示已下载到本地的图片文件；交互与在线阅读器保持一致：
/// - 三种阅读方向（上下滚动 / 左右翻页 / 从右至左）与在线阅读器同步；
/// - 点击页面任意位置：弹出/隐藏顶部与底部弹窗（与在线阅读器一致）；
/// - 顶部弹窗：标题 + 返回；底部弹窗：进度条 + 设置/浅色/深色切换 + 页码指示；
/// - 弹层出入场动画（上滑/下滑 + 淡入淡出）、双指缩放。
class LocalReaderPage extends StatefulWidget {
  const LocalReaderPage({super.key});

  @override
  State<LocalReaderPage> createState() => _LocalReaderPageState();
}

class _LocalReaderPageState extends State<LocalReaderPage> {
  final PageController _pageCtrl = PageController();
  final ScrollController _listCtrl = ScrollController();
  final Map<int, BuildContext> _itemCtx = <int, BuildContext>{};

  /// 双击放大变换控制器：单击切菜单，双击围绕点击位置 1x↔2.5x；
  /// 双手指缩放由 InteractiveViewer 默认行为处理（maxScale=4）。
  final TransformationController _xCtrl = TransformationController();
  bool _doubleTapZoomed = false;

  /// 当前按下的指针数：≥2 时临时禁用 PageView 滚动，避免其横向拖动
  /// 在手势竞技场中抢走 InteractiveViewer 的双指缩放。
  int _activePointers = 0;

  /// 双击位置（onDoubleTapDown 捕获），用于围绕点击位置缩放。
  Offset _doubleTapPos = Offset.zero;

  List<String> _files = <String>[];
  String _title = '';
  int _currentPage = 0;
  bool _barVisible = true;
  ReadDirection _lastDirection = ReadDirection.vertical;
  Timer? _hideBarTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_files.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _title = args['title']?.toString() ?? '本地阅读';
        final raw = args['files'];
        if (raw is List) {
          _files = raw.map((e) => e.toString()).toList();
        }
      }
    }
  }

  @override
  void dispose() {
    _hideBarTimer?.cancel();
    _pageCtrl.dispose();
    _listCtrl.dispose();
    _xCtrl.dispose();
    super.dispose();
  }

  /// 双击：在 1x 与 2.5x 之间切换缩放（围绕双击位置放大）。
  /// 上下滚动模式没有 InteractiveViewer，双击不缩放。
  void _toggleDoubleTapZoom() {
    if (_direction == ReadDirection.vertical) return;
    setState(() {
      if (_doubleTapZoomed) {
        _doubleTapZoomed = false;
        _xCtrl.value = Matrix4.identity();
        return;
      }
      _doubleTapZoomed = true;
      // 围绕双击位置缩放：平移到点击点 × 缩放 × 平移回原点
      final p = _doubleTapPos;
      _xCtrl.value = Matrix4.identity()
        ..translateByDouble(p.dx, p.dy, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1)
        ..translateByDouble(-p.dx, -p.dy, 0, 1);
      if (_barVisible) {
        _barVisible = false;
        _hideBarTimer?.cancel();
      }
    });
  }

  /// 翻页后重置缩放（_xCtrl 为所有页共享）。
  void _resetZoom() {
    if (!_doubleTapZoomed && _xCtrl.value == Matrix4.identity()) {
      return;
    }
    _doubleTapZoomed = false;
    _xCtrl.value = Matrix4.identity();
  }

  ReadDirection get _direction => context.read<AppState>().readDirection;

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) {
      _scheduleHideBar();
    } else {
      _hideBarTimer?.cancel();
    }
  }

  void _scheduleHideBar() {
    _hideBarTimer?.cancel();
    _hideBarTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _barVisible) {
        setState(() => _barVisible = false);
      }
    });
  }

  void _jumpToPage(int i) {
    if (i < 0 || i >= _files.length) return;
    if (_direction == ReadDirection.vertical) {
      final ctx = _itemCtx[i];
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 0.0);
      } else if (_listCtrl.hasClients) {
        final pos = _listCtrl.position;
        final avg = pos.maxScrollExtent > 0
            ? pos.maxScrollExtent / (_files.isEmpty ? 1 : _files.length)
            : pos.viewportDimension;
        _listCtrl.jumpTo((i * avg).clamp(0.0, pos.maxScrollExtent));
      }
    } else if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(i);
    }
    setState(() => _currentPage = i);
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
      return false;
    }
    if (_itemCtx.isEmpty) return false;
    _itemCtx.removeWhere((k, c) => !c.mounted);
    int? found;
    double bestTop = double.infinity;
    for (final entry in _itemCtx.entries) {
      final ro = entry.value.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final top = ro.localToGlobal(Offset.zero).dy;
      final bottom = top + ro.size.height;
      if (top <= 10 && bottom > 10 && top < bestTop) {
        bestTop = top;
        found = entry.key;
      }
    }
    if (found != null && found != _currentPage) {
      // 闭包内不能依赖外部 `found != null` 的类型提升（Dart 限制），
      // 故先用 non-nullable 局部变量接住，再交给 setState。
      final newPage = found;
      setState(() => _currentPage = newPage);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // 方向切换后保持当前页。
    if (_lastDirection != app.readDirection) {
      _lastDirection = app.readDirection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToPage(_currentPage);
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          // 内容层：整页可点击，弹出/隐藏顶底弹窗
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 单击切换上下菜单；双击围绕点击位置 1x↔2.5x 缩放；
              // 双手指缩放由 InteractiveViewer 默认行为处理。
              onTap: _toggleBar,
              onDoubleTapDown: (TapDownDetails d) =>
                  _doubleTapPos = d.localPosition,
              onDoubleTap: _toggleDoubleTapZoom,
              child: _buildContent(),
            ),
          ),
          // 顶部弹窗：标题 + 返回
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _barVisible
                  ? Offset.zero
                  : const Offset(0, -1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _barVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_barVisible,
                  child: _buildTopOverlay(),
                ),
              ),
            ),
          ),
          // 底部弹窗：进度条 + 设置/深色切换 + 页码
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _barVisible
                  ? Offset.zero
                  : const Offset(0, 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _barVisible ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_barVisible,
                  child: _buildBottomOverlay(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_files.isEmpty) {
      return const Center(
        child: Text('无图片数据', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_direction == ReadDirection.vertical) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          key: const ValueKey<String>('local-reader-vertical'),
          controller: _listCtrl,
          itemCount: _files.length,
          itemBuilder: (BuildContext c, int i) => _MeasuredItem(
            index: i,
            registry: _itemCtx,
            child: _verticalImage(i),
          ),
        ),
      );
    }
    final rtl = _direction == ReadDirection.rightToLeft;
    // Listener 统计活跃指针：双指触控时临时禁用 PageView 滚动，
    // 让 InteractiveViewer 的缩放手势在竞技场中获胜。
    return Listener(
      onPointerDown: (PointerDownEvent e) {
        _activePointers++;
        if (_activePointers == 2) setState(() {});
      },
      onPointerUp: (PointerUpEvent e) {
        _activePointers = (_activePointers - 1).clamp(0, 8);
        if (_activePointers == 1) setState(() {});
      },
      onPointerCancel: (PointerCancelEvent e) {
        _activePointers = (_activePointers - 1).clamp(0, 8);
        if (_activePointers == 1) setState(() {});
      },
      child: PageView.builder(
        key: ValueKey<String>('local-reader-paged-$rtl'),
        controller: _pageCtrl,
        scrollDirection: Axis.horizontal,
        reverse: rtl,
        // 双指触控期间禁用翻页手势（null = 平台默认翻页物理）
        physics: _activePointers > 1
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: _files.length,
        onPageChanged: (int i) {
          _resetZoom();
          setState(() => _currentPage = i);
          if (_barVisible) _scheduleHideBar();
        },
        itemBuilder: (_, i) {
          final f = File(_files[i]);
          return InteractiveViewer(
            transformationController: _xCtrl,
            minScale: 1.0,
            maxScale: 4,
            panEnabled: true,
            // 双指捏合缩回 1x 时自动复位
            onInteractionEnd: (ScaleEndDetails d) {
              final s = _xCtrl.value.getMaxScaleOnAxis();
              if (s < 1.05 && _doubleTapZoomed) {
                setState(() {
                  _doubleTapZoomed = false;
                  _xCtrl.value = Matrix4.identity();
                });
              }
            },
            child: Center(
              child: f.existsSync()
                  ? Image.file(f, fit: BoxFit.contain, gaplessPlayback: true)
                  : const Icon(Icons.broken_image_rounded,
                      color: Colors.white24, size: 42),
            ),
          );
        },
      ),
    );
  }

  /// 上下滚动模式的单页：图片按宽度铺满、顶对齐、上下无缝紧贴。
  Widget _verticalImage(int i) {
    final f = File(_files[i]);
    if (!f.existsSync()) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded,
            color: Colors.white24, size: 42),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW =
        (MediaQuery.sizeOf(context).width * dpr).round().clamp(360, 2048);
    return Image.file(
      f,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      cacheWidth: decodeW,
      errorBuilder: (_, _, _) => const SizedBox(
        height: 320,
        child: Center(
          child: Icon(Icons.broken_image_rounded,
              color: Colors.white24, size: 42),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
          child: Row(
            children: <Widget>[
              // 返回按键移到左上角，与在线阅读器一致
              IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final app = context.watch<AppState>();
    final isDark = app.scheme.isDark;
    final maxPage = (_files.length - 1).clamp(0, 1 << 30).toDouble();
    return SafeArea(
      top: false,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.9),
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('$_currentPage',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor:
                            Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        min: 0,
                        max: maxPage,
                        value: _currentPage.toDouble().clamp(0.0, maxPage),
                        onChanged: (double v) {
                          final i = v.round();
                          setState(() => _currentPage = i);
                          _jumpToPage(i);
                        },
                      ),
                    ),
                  ),
                  Text('${_files.length}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
              // 与在线阅读器一致：操作行（设置 + 浅色/深色 + 页码）
              Row(
                children: <Widget>[
                  _OverlayAction(
                    icon: Icons.tune_rounded,
                    label: '设置',
                    onTap: _showSettings,
                  ),
                  const SizedBox(width: 20),
                  _OverlayAction(
                    icon: isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: isDark ? '浅色' : '深色',
                    onTap: _toggleTheme,
                  ),
                  const Spacer(),
                  Text(
                    '${_currentPage + 1} / ${_files.length}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleTheme() {
    final app = context.read<AppState>();
    app.setScheme(
      app.scheme.isDark ? ThemeScheme.lightOrange : ThemeScheme.darkOrange,
    );
  }

  void _showSettings() {
    _hideBarTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetCtx) {
        return Consumer<AppState>(
          builder: (BuildContext c, AppState app, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '阅读设置',
                      style: Theme.of(c).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '翻页方向',
                      style: Theme.of(c).textTheme.labelMedium?.copyWith(
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ReadDirection>(
                      segments: const <ButtonSegment<ReadDirection>>[
                        ButtonSegment<ReadDirection>(
                            value: ReadDirection.vertical,
                            label: Text('上下滚动')),
                        ButtonSegment<ReadDirection>(
                            value: ReadDirection.horizontal,
                            label: Text('左右翻页')),
                        ButtonSegment<ReadDirection>(
                            value: ReadDirection.rightToLeft,
                            label: Text('从右至左')),
                      ],
                      selected: <ReadDirection>{app.readDirection},
                      onSelectionChanged: (Set<ReadDirection> s) =>
                          app.setReadDirection(s.first),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('阅读时屏幕常亮'),
                      value: app.keepScreenOn,
                      onChanged: (bool v) => app.setKeepScreenOn(v),
                    ),
                    Row(
                      children: <Widget>[
                        const Text('预加载页数'),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '${app.preLoad}',
                            value: app.preLoad.clamp(1, 10).toDouble(),
                            onChanged: (double v) => app.setPreLoad(v.round()),
                          ),
                        ),
                        Text('${app.preLoad} 页'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (mounted && _barVisible) _scheduleHideBar();
    });
  }
}

/// 条目包装：注册自身 BuildContext，用于垂直模式的当前页定位与精准跳转。
class _MeasuredItem extends StatefulWidget {
  const _MeasuredItem({
    required this.index,
    required this.registry,
    required this.child,
  });

  final int index;
  final Map<int, BuildContext> registry;
  final Widget child;

  @override
  State<_MeasuredItem> createState() => _MeasuredItemState();
}

class _MeasuredItemState extends State<_MeasuredItem> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.registry[widget.index] = context;
  }

  @override
  void dispose() {
    if (widget.registry[widget.index] == context) {
      widget.registry.remove(widget.index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 底部弹窗操作项（图标 + 文字）。
class _OverlayAction extends StatelessWidget {
  const _OverlayAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 19, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
