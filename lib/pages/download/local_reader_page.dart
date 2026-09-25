import 'dart:io';

import 'package:flutter/material.dart';

/// 本地离线阅读器（对齐 qt local_read_view）。
///
/// 直接展示已下载到本地的图片文件；交互与在线阅读器保持一致：
/// 点击翻页、顶/底渐变弹层（返回键 + 进度滑杆 + 页码指示）、
/// 弹层出入场动画（上滑/下滑 + 淡入淡出）、双指缩放。
class LocalReaderPage extends StatefulWidget {
  const LocalReaderPage({super.key});

  @override
  State<LocalReaderPage> createState() => _LocalReaderPageState();
}

class _LocalReaderPageState extends State<LocalReaderPage> {
  final PageController _pageCtrl = PageController();
  List<String> _files = <String>[];
  String _title = '';
  int _currentPage = 0;
  bool _barVisible = true;

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
    _pageCtrl.dispose();
    super.dispose();
  }

  void _toggleBar() => setState(() => _barVisible = !_barVisible);

  void _onTap(TapUpDetails d, BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final x = d.globalPosition.dx;
    if (x < w / 3) {
      _prev();
    } else if (x > w * 2 / 3) {
      _next();
    } else {
      _toggleBar();
    }
  }

  void _next() {
    if (_currentPage < _files.length - 1) {
      _pageCtrl.animateToPage(_currentPage + 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic);
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageCtrl.animateToPage(_currentPage - 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          // 内容层：整页可点击（左/中/右翻页或呼出弹层）
          Positioned.fill(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _files.length,
              onPageChanged: (int i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) {
                final f = File(_files[i]);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) => _onTap(d, context),
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: f.existsSync()
                          ? Image.file(f,
                              fit: BoxFit.contain, gaplessPlayback: true)
                          : const Icon(Icons.broken_image_rounded,
                              color: Colors.white24, size: 42),
                    ),
                  ),
                );
              },
            ),
          ),
          // 顶部弹层：标题 + 返回（出入场动画，隐藏时不拦截点击）
          _overlay(top: true, child: _buildTopOverlay()),
          // 底部弹层：进度滑杆 + 页码指示
          _overlay(top: false, child: _buildBottomOverlay()),
        ],
      ),
    );
  }

  /// 顶/底弹层统一包装：出入场 = 上/下滑 + 淡入淡出，
  /// 隐藏时不拦截点击（与在线阅读器一致）。
  Widget _overlay({required bool top, required Widget child}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _barVisible
            ? Offset.zero
            : (top ? const Offset(0, -1) : const Offset(0, 1)),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _barVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: IgnorePointer(ignoring: !_barVisible, child: child),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
          child: Row(
            children: <Widget>[
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
              IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
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
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
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
                        max: (_files.length - 1).clamp(0, 1 << 30).toDouble(),
                        value: _currentPage.toDouble(),
                        onChanged: (double v) {
                          final i = v.round();
                          setState(() => _currentPage = i);
                          _pageCtrl.jumpToPage(i);
                        },
                      ),
                    ),
                  ),
                  Text('${_files.length}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
              Row(
                children: <Widget>[
                  Text(
                    '${_currentPage + 1} / ${_files.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  const Text(
                    '离线阅读',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
