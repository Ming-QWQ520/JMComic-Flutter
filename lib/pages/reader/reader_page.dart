import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../core/utils/scramble.dart';
import '../../state/app_state.dart';

/// 阅读器页。
///
/// 交互（对齐需求）：
/// - 点击页面任意位置：弹出/隐藏顶部与底部弹窗；
/// - 顶部弹窗：左侧漫画名称，右上角返回按键；
/// - 底部弹窗：进度条位于底部弹窗上方，弹窗内有「设置」与
///   「深色/浅色」切换；进度条固定在屏幕底部，显示期间页面
///   仍可正常滚动/翻页（拖动进度条时不会自动隐藏）；
/// - 上下滚动模式图片无缝紧贴（消除黑色间隔）；
/// - 音量键翻页、键盘方向键翻页、预加载、屏幕常亮保持不变。
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const MethodChannel _channel = MethodChannel(
    'com.ming.jmcomic/volume',
  );

  /// 内存页缓存上限（超出后按"离当前页最远"淘汰，防止长篇 OOM）。
  static const int _cacheLimit = 48;

  final JmApi _api = JmApi.instance;
  final PageController _pageCtrl = PageController();
  final ScrollController _listCtrl = ScrollController();
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
  final Set<int> _failedPages = <int>{};

  /// 上下滚动模式下各条目的 BuildContext（用于定位当前页与精准跳转）。
  final Map<int, BuildContext> _itemCtx = <int, BuildContext>{};

  bool _barVisible = true;
  bool _scrambled = false;
  int _currentPage = 0;
  bool _draggingSlider = false;
  ReadDirection _lastDirection = ReadDirection.vertical;
  Timer? _hideBarTimer;

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
      _load();
      _setupNative();
    }
  }

  @override
  void dispose() {
    _hideBarTimer?.cancel();
    _pageCtrl.dispose();
    _listCtrl.dispose();
    _focus.dispose();
    _channel.setMethodCallHandler(null);
    // 离开阅读器：关闭常亮与音量键拦截
    _channel
        .invokeMethod('keepScreenOn', <String, dynamic>{'enabled': false})
        .catchError((_) {});
    _channel
        .invokeMethod('setEnabled', <String, dynamic>{'enabled': false})
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
        await _channel.invokeMethod('keepScreenOn', <String, dynamic>{
          'enabled': true,
        });
      } catch (_) {}
    }
    if (app.volumeKeyPaging) {
      try {
        await _channel.invokeMethod('setEnabled', <String, dynamic>{
          'enabled': true,
        });
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
      setState(() {
        _cache[index] = bytes;
        _trimCache();
        _failedPages.remove(index);
      });
      return bytes;
    } catch (_) {
      if (mounted) {
        setState(() => _failedPages.add(index));
      }
      return null;
    } finally {
      _pending.remove(index);
    }
  }

  /// 缓存超限时淘汰离当前页最远的字节，保证长时间阅读不 OOM。
  void _trimCache() {
    if (_cache.length <= _cacheLimit) return;
    final evictable =
        _cache.keys.where((k) => (k - _currentPage).abs() > 6).toList()..sort(
          (a, b) =>
              (b - _currentPage).abs().compareTo((a - _currentPage).abs()),
        );
    final need = _cache.length - _cacheLimit;
    for (var i = 0; i < need && i < evictable.length; i++) {
      _cache.remove(evictable[i]);
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
      _jumpToPage(_currentPage + 1);
    } else {
      _toast('已经是最后一页');
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _jumpToPage(_currentPage - 1);
    } else {
      _toast('已经是第一页');
    }
  }

  /// 翻页统一入口：垂直模式滚动列表，水平/日漫模式 PageView。
  void _jumpToPage(int i) {
    if (_direction == ReadDirection.vertical) {
      _scrollToPage(i);
    } else if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(i);
    }
    _preload(i + 1);
  }

  /// 垂直模式精准跳转：优先 ensureVisible，未构建时按平均页高估算，
  /// 落点后下一帧校正。
  void _scrollToPage(int i) {
    if (!_listCtrl.hasClients) return;
    final ctx = _itemCtx[i];
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 0.0);
      return;
    }
    final pos = _listCtrl.position;
    final avg = pos.maxScrollExtent > 0
        ? pos.maxScrollExtent / (_images.isEmpty ? 1 : _images.length)
        : pos.viewportDimension;
    final target = (i * avg).clamp(0.0, pos.maxScrollExtent);
    _listCtrl.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c2 = _itemCtx[i];
      if (mounted && c2 != null && c2.mounted) {
        Scrollable.ensureVisible(c2, duration: Duration.zero, alignment: 0.0);
      }
    });
  }

  /// 滚动时同步当前页码（取视口顶部所压住的条目）并触发预加载。
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
      // 视口顶部（y≈10）压在哪个条目上，即当前阅读页
      if (top <= 10 && bottom > 10 && top < bestTop) {
        bestTop = top;
        found = entry.key;
      }
    }
    if (found != null && found != _currentPage) {
      final target = found; // 提升进闭包前先固化为 final 局部变量
      setState(() => _currentPage = target);
      _preload(target + 1);
    }
    return false;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 800),
        ),
      );
  }

  // ------------------------------------------------------------------
  // 弹窗（顶部/底部）
  // ------------------------------------------------------------------

  /// 点击任意位置：弹出/隐藏顶部与底部弹窗。
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
    if (_draggingSlider) return; // 拖动进度条期间绝不自动隐藏
    _hideBarTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _barVisible && !_draggingSlider) {
        setState(() => _barVisible = false);
      }
    });
  }

  /// 深色/浅色切换（写入全局主题，持久化）。
  void _toggleTheme() {
    final app = context.read<AppState>();
    app.setScheme(
      app.scheme.isDark ? ThemeScheme.lightOrange : ThemeScheme.darkOrange,
    );
  }

  /// 设置面板：翻页方向 / 音量键翻页 / 屏幕常亮 / 预加载页数。
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
                          label: Text('上下滚动'),
                        ),
                        ButtonSegment<ReadDirection>(
                          value: ReadDirection.horizontal,
                          label: Text('左右翻页'),
                        ),
                        ButtonSegment<ReadDirection>(
                          value: ReadDirection.rightToLeft,
                          label: Text('从右至左'),
                        ),
                      ],
                      selected: <ReadDirection>{app.readDirection},
                      onSelectionChanged: (Set<ReadDirection> s) =>
                          app.setReadDirection(s.first),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('音量键翻页'),
                      value: app.volumeKeyPaging,
                      onChanged: (bool v) => app.setVolumeKeyPaging(v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('阅读时屏幕常亮'),
                      value: app.keepScreenOn,
                      onChanged: (bool v) {
                        app.setKeepScreenOn(v);
                        _channel
                            .invokeMethod('keepScreenOn', <String, dynamic>{
                              'enabled': v,
                            })
                            .catchError((_) {});
                      },
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

  // ------------------------------------------------------------------
  // 构建
  // ------------------------------------------------------------------

  ReadDirection get _direction => context.read<AppState>().readDirection;

  @override
  Widget build(BuildContext context) {
    // watch：主题/方向/音量键等全局设置变化时即时生效
    final app = context.watch<AppState>();
    // 方向切换后保持当前页（含设置面板里的切换）
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
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleBar,
                child: _buildContent(),
              ),
            ),
          ),
          // 顶部弹窗：漫画名称 + 右上角返回
          // 弹出/隐藏带动画（上滑淡入 / 上滑淡出），隐藏时不拦截点击。
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
          // 底部弹窗：进度条在上方，设置/深浅色在下方
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
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.6),
            SizedBox(height: 14),
            Text(
              '正在加载章节图片…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
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
        child: Text('无图片数据', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_direction == ReadDirection.vertical) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          key: const ValueKey<String>('reader-vertical'),
          controller: _listCtrl,
          itemCount: _images.length,
          itemBuilder: (BuildContext c, int i) => _MeasuredItem(
            index: i,
            registry: _itemCtx,
            child: _verticalImage(i),
          ),
        ),
      );
    }
    final rtl = _direction == ReadDirection.rightToLeft;
    return PageView.builder(
      key: ValueKey<String>('reader-paged-$rtl'),
      scrollDirection: Axis.horizontal,
      reverse: rtl,
      controller: _pageCtrl,
      itemCount: _images.length,
      onPageChanged: (int i) {
        setState(() => _currentPage = i);
        _preload(i + 1);
        if (_barVisible) _scheduleHideBar();
      },
      itemBuilder: (BuildContext c, int i) => _pageImage(i),
    );
  }

  /// 上下滚动模式的单页：图片按宽度铺满、顶对齐、上下无缝紧贴，
  /// 彻底消除 PageView 分页带来的黑色间隔。
  Widget _verticalImage(int i) {
    final bytes = _cache[i];
    if (bytes == null) {
      if (_failedPages.contains(i)) {
        return _failedPage(i, placeholderHeight: _estPageHeight);
      }
      _loadImage(i);
      return Container(
        height: _estPageHeight,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${i + 1} / ${_images.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      // 按屏幕宽度×DPR 解码：长图原图常达数万像素高，
      // 限制解码尺寸可显著降低内存占用与首次解码耗时。
      cacheWidth: _decodeWidth,
    );
  }

  /// 占位高度：未知尺寸时取视口宽 × 1.4（JM 常见长图比例）。
  double get _estPageHeight {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 1.4).clamp(320.0, 2400.0);
  }

  /// 上下滚动模式的图片解码宽度（视口宽 × DPR，上限 2048）。
  int get _decodeWidth {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (MediaQuery.sizeOf(context).width * dpr).round().clamp(360, 2048);
  }

  /// 左右/日漫模式的图片解码宽度：预留 2 倍余量供双指缩放。
  int get _pagedDecodeWidth => _decodeWidth * 2;

  /// 左右/日漫模式的单页：整页 contain 居中 + 双指缩放。
  Widget _pageImage(int i) {
    final bytes = _cache[i];
    if (bytes == null) {
      if (_failedPages.contains(i)) {
        return _failedPage(i);
      }
      _loadImage(i);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${i + 1} / ${_images.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: _pagedDecodeWidth,
        ),
      ),
    );
  }

  Widget _failedPage(int i, {double? placeholderHeight}) {
    return Container(
      height: placeholderHeight,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white70,
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            '第 ${i + 1} 页加载失败',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _failedPages.remove(i));
              _loadImage(i);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 顶部弹窗：左侧漫画名称，右上角返回按键。
  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          // 吸收弹窗区域的点击，不透传到内容层
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
                    _title.isEmpty ? '阅读' : _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // 右上角返回按键
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部弹窗：进度条位于弹窗上方；弹窗内提供设置与深色/浅色切换。
  /// 弹窗只覆盖底部一条区域，其余页面区域仍可正常滚动/翻页。
  Widget _buildBottomOverlay() {
    final app = context.watch<AppState>();
    final isDark = app.scheme.isDark;
    final maxPage = (_images.length - 1).clamp(0, 1 << 30).toDouble();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          // 吸收弹窗区域的点击，不透传到内容层
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
                // —— 进度条（固定在屏幕底部、位于底部弹窗上方） ——
                Row(
                  children: <Widget>[
                    Text(
                      '$_currentPage',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          activeTrackColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          min: 0,
                          max: maxPage,
                          value: _currentPage.toDouble().clamp(0.0, maxPage),
                          onChangeStart: (double v) {
                            _draggingSlider = true;
                            _hideBarTimer?.cancel();
                          },
                          onChanged: (double v) {
                            final i = v.round();
                            if (i != _currentPage) {
                              setState(() => _currentPage = i);
                              _jumpToPage(i);
                            }
                          },
                          onChangeEnd: (double v) {
                            _draggingSlider = false;
                            _scheduleHideBar();
                          },
                        ),
                      ),
                    ),
                    Text(
                      '${_images.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                // —— 底部弹窗操作行：设置 + 深色/浅色 ——
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
                      '${_currentPage + 1} / ${_images.length}',
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
      ),
    );
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
  void initState() {
    super.initState();
    widget.registry[widget.index] = context;
  }

  @override
  void didUpdateWidget(_MeasuredItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (oldWidget.registry[oldWidget.index] == context) {
        oldWidget.registry.remove(oldWidget.index);
      }
      widget.registry[widget.index] = context;
    }
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
