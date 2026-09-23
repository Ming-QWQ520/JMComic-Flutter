import 'dart:io';

import 'package:flutter/material.dart';

/// 本地离线阅读器（对齐 qt local_read_view）。
///
/// 直接展示已下载到本地的图片文件，交互与在线阅读器一致：
/// 点击翻页、页码滑杆、缩放。
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
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _barVisible
          ? AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              title: Text(_title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (TapUpDetails d) => _onTap(d, context),
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: _files.length,
          onPageChanged: (int i) => setState(() => _currentPage = i),
          itemBuilder: (_, i) {
            final f = File(_files[i]);
            return InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: f.existsSync()
                    ? Image.file(f,
                        fit: BoxFit.contain, gaplessPlayback: true)
                    : const Icon(Icons.broken_image_rounded,
                        color: Colors.white24, size: 42),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _barVisible ? _buildBottomBar() : null,
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(
          children: <Widget>[
            Text('$_currentPage',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Theme.of(context).colorScheme.primary,
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
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
