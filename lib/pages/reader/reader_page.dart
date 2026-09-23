import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../core/utils/scramble.dart';
import '../../state/app_state.dart';

/// 阅读器页。
///
/// 功能：
/// - 章节图片加载与乱序还原（album_id >= scramble_id 时）；
/// - 音量键翻页（原生 MethodChannel 拦截，可在设置关闭）；
/// - 上下 / 左右翻页方向切换，键盘方向键翻页；
/// - 点击左/右 1/3 区域翻页，中间呼出工具栏；
/// - 下一页预加载、页码滑杆跳转、阅读时屏幕常亮。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const MethodChannel _channel =
      MethodChannel('com.ming.jmcomic/volume');

  final JmApi _api = JmApi.instance;
  final PageController _pageCtrl = PageController();
  final FocusNode _focus = FocusNode();

  String _albumId = '';
  String _chapterId = '';
  String _title = '';
  bool _loading = true;
  String _error = '';
  List<ReadImage> _images = <ReadImage>[];

  // 图片字节缓存（页码 → 已还原图片字节）
  final Map<int, Uint8List> _cache = <int, Uint8List>{};
  final Set<int> _pending = <int>{};

  bool _barVisible = true;
  bool _scrambled = false;
  int _currentPage = 0;
  Timer? _hideBarTimer;

  ReadDirection _direction = ReadDirection.vertical;
  bool _volumeKeys = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_albumId.isEmpty) {
      final args =
          (ModalRoute.of(context)?.settings.arguments as Map?)
              ?.cast<String, String>() ??
              const <String, String>{};
      _albumId = args['albumId'] ?? '';
      _chapterId = args['chapterId'] ?? '';
      _title = args['title'] ?? '';
      final app = context.read<AppState>();
      _direction = app.readDirection;
      _volumeKeys = app.volumeKeyPaging;
      _load();
      _setupNative();
    }
  }

  @override
  void dispose() {
    _hideBarTimer?.cancel();
    _pageCtrl.dispose();
    _focus.dispose();
    _channel.setMethodCallHandler(null);
    // 离开阅读器：关闭常亮与音量键拦截
    _channel.invokeMethod('keepScreenOn', <String, dynamic>{'enabled': false})
        .catchError((_) {});
    _channel.invokeMethod('setEnabled', <String, dynamic>{'enabled': false})
        .catchError((_) {});
    super.dispose();
  }

  Future<void> _setupNative() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volume') {
        if (call.arguments == 'up') {
          _prevPage();
        } else {
          _nextPage();
        }
      }
      return null;
    });
    // 屏幕常亮（原生 FLAG_KEEP_SCREEN_ON）
    final app = context.read<AppState>();
    if (app.keepScreenOn) {
      try {
        await _channel.invokeMethod(
            'keepScreenOn', <String, dynamic>{'enabled': true});
      } catch (_) {}
    }
    if (_volumeKeys) {
      try {
        await _channel
            .invokeMethod('setEnabled', <String, dynamic>{'enabled': true});
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    if (_chapterId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的章节 ID';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      // 对齐 qt 阅读流程：comic_read 获取图片列表，scramble_id 优先从
      // chapter_view_template 获取（特殊签名头），失败用响应内字段
      final read = await _api.getComicRead(_chapterId);
      var sid = 0;
      try {
        sid = await _api.getScrambleId(_chapterId);
      } catch (_) {
        sid = int.tryParse(read.scrambleId) ?? 220980;
      }
      if (sid == 0) sid = int.tryParse(read.scrambleId) ?? 0;
      if (!mounted) return;
      final aid = int.tryParse(_albumId) ?? 0;
      setState(() {
        _images = read.images;
        _scrambled = Scramble.needScramble(aid, sid);
        _loading = false;
      });
      if (_images.isNotEmpty) {
        _loadImage(0);
        _preload(1);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 页面图片获取（含乱序还原），结果进缓存。
  Future<Uint8List?> _loadImage(int index) async {
    if (index < 0 || index >= _images.length) return null;
    if (_cache.containsKey(index)) return _cache[index];
    if (_pending.contains(index)) return null;
    _pending.add(index);
    try {
      final url = _images[index].image;
      final raw = await _api.downloadImage(url);
      Uint8List bytes = Uint8List.fromList(raw);
      final isGif = url.toLowerCase().endsWith('.gif');
      if (_scrambled && !isGif) {
        final name = Scramble.filenameFromUrl(url);
        try {
          bytes = await Scramble.descramble(bytes, _albumId, name);
        } catch (_) {
          // 还原失败时使用原图兜底
        }
      }
      if (!mounted) return bytes;
      setState(() => _cache[index] = bytes);
      return bytes;
    } catch (_) {
      if (mounted) setState(() {});
      return null;
    } finally {
      _pending.remove(index);
    }
  }

  void _preload(int index) {
    final n = context.read<AppState>().preLoad;
    for (var i = index; i < index + n && i < _images.length; i++) {
      _loadImage(i);
    }
  }

  void _nextPage() {
    if (_currentPage < _images.length - 1) {
      _jumpTo(_currentPage + 1);
    } else {
      _toast('已经是最后一页');
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _jumpTo(_currentPage - 1);
    } else {
      _toast('已经是第一页');
    }
  }

  void _jumpTo(int i) {
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _preload(i + 1);
    _scheduleHideBar();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 800),
      ));
  }

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) _scheduleHideBar();
  }

  void _scheduleHideBar() {
    _hideBarTimer?.cancel();
    _hideBarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _barVisible) {
        setState(() => _barVisible = false);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _prevPage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _barVisible ? _buildAppBar() : null,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) => _onTap(d, context),
          child: _buildContent(),
        ),
      ),
      bottomNavigationBar: _barVisible ? _buildBottomBar() : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
          ),
        ),
      ),
      title: Text(
        _title.isEmpty ? '阅读' : _title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: <Widget>[
        IconButton(
          tooltip: switch (_direction) {
            ReadDirection.vertical => '当前: 上下翻页',
            ReadDirection.horizontal => '当前: 左右翻页',
            ReadDirection.rightToLeft => '当前: 日漫(右到左)',
          },
          icon: Icon(
            _direction == ReadDirection.vertical
                ? Icons.swap_vert_rounded
                : Icons.swap_horiz_rounded,
          ),
          onPressed: () {
            final app = context.read<AppState>();
            final d = switch (_direction) {
              ReadDirection.vertical => ReadDirection.horizontal,
              ReadDirection.horizontal => ReadDirection.rightToLeft,
              ReadDirection.rightToLeft => ReadDirection.vertical,
            };
            setState(() => _direction = d);
            app.setReadDirection(d);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _pageCtrl.jumpToPage(_currentPage);
                _focus.requestFocus();
              }
            });
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// 点击翻页：左 1/3 上一页，右 1/3 下一页，中间呼出/隐藏工具栏。
  void _onTap(TapUpDetails d, BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final x = d.globalPosition.dx;
    if (x < w / 3) {
      _prevPage();
    } else if (x > w * 2 / 3) {
      _nextPage();
    } else {
      _toggleBar();
    }
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.6),
            SizedBox(height: 14),
            Text('正在加载章节图片…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_images.isEmpty) {
      return const Center(
          child: Text('无图片数据', style: TextStyle(color: Colors.white70)));
    }
    final rtl = _direction == ReadDirection.rightToLeft;
    final axis = _direction == ReadDirection.vertical
        ? Axis.vertical
        : Axis.horizontal;
    return PageView.builder(
      key: ValueKey<String>('axis-$axis-$rtl'),
      scrollDirection: axis,
      reverse: rtl,
      controller: _pageCtrl,
      itemCount: _images.length,
      onPageChanged: (int i) {
        setState(() => _currentPage = i);
        _preload(i + 1);
        _scheduleHideBar();
      },
      itemBuilder: (BuildContext c, int i) => _pageImage(i),
    );
  }

  Widget _pageImage(int i) {
    final bytes = _cache[i];
    if (bytes == null) {
      _loadImage(i);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('${i + 1} / ${_images.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: Colors.white60),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ),
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
                  max: (_images.length - 1).clamp(0, 1 << 30).toDouble(),
                  value: _currentPage.toDouble(),
                  onChanged: (double v) {
                    final i = v.round();
                    setState(() => _currentPage = i);
                    _pageCtrl.jumpToPage(i);
                    _preload(i + 1);
                  },
                ),
              ),
            ),
            Text('${_images.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

