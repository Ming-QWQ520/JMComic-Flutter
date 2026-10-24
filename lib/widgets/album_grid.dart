import 'package:flutter/material.dart';

import '../core/protocol/models.dart';
import 'album_card.dart';
import 'feedback.dart';

/// 无限滚动专辑网格（最新/搜索/分类/收藏/历史等复用）。
///
/// [usePrimaryScroll] = 嵌套在 NestedScrollView（发现页）内时置 true：
/// 不再传入自有 ScrollController，让 GridView 自动绑定 NestedScrollView
/// 提供的内部 PrimaryScrollController，实现内滚到顶后平滑接管外层
/// header 展开手势（修复「最新上架滑动到顶后无法回到顶部而是直接刷新」）。
/// [enableRefresh] = 是否启用内部下拉刷新；NestedScrollView 内应关闭，
/// 避免内层 overscroll 弹跳误触发刷新（外层 header 展开应交给外层）。
class AlbumGrid extends StatefulWidget {
  const AlbumGrid({
    super.key,
    required this.fetchPage,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    this.usePrimaryScroll = false,
    this.enableRefresh = true,
  });

  /// 返回 null 表示失败；空数组表示没有更多。
  final Future<List<SearchAlbum>?> Function(int page) fetchPage;
  final EdgeInsetsGeometry padding;

  /// 嵌套在 NestedScrollView 内时：绑定外层提供的 PrimaryScrollController。
  final bool usePrimaryScroll;

  /// 是否启用内部下拉刷新（NestedScrollView 内应关闭）。
  final bool enableRefresh;

  @override
  State<AlbumGrid> createState() => AlbumGridState();
}

class AlbumGridState extends State<AlbumGrid> {
  final List<SearchAlbum> _items = <SearchAlbum>[];

  /// 自有滚动控制器（仅在 [AlbumGrid.usePrimaryScroll] = false 时使用，
  /// 用于监听触底加载更多；嵌套模式下必须让位给外层 inner controller）。
  ScrollController? _scroll;

  /// 已加载条目的 ID 集合（用于判重终止，见 [_loadMore]）。
  final Set<String> _seenIds = <String>{};

  int _page = 1;
  bool _loading = false;
  bool _failed = false;
  bool _noMore = false;

  /// 最近一次失败的具体原因（透传给用户，避免盲拆）。
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    if (!widget.usePrimaryScroll) {
      _scroll = ScrollController()..addListener(_onScroll);
    }
    _loadMore();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_onScroll);
    _scroll?.dispose();
    super.dispose();
  }

  /// 触底预加载：自有 controller 模式直接监听；嵌套模式下通过
  /// 滚动通知（NotificationListener，depth==0 仅限本网格自身）。
  void _onScroll() {
    final s = _scroll;
    if (s == null) return;
    if (s.position.pixels >= s.position.maxScrollExtent - 700) {
      _loadMore();
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 700) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_loading || _noMore || _failed) return;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final list = await widget.fetchPage(_page);
      if (!mounted) return;
      if (list == null) {
        _failed = _items.isEmpty; // 有内容时静默失败
        if (_items.isNotEmpty) _noMore = true;
      } else {
        // 关键修复（搜索/分类/最新等列表无限重复渲染的根因）：
        // JM 服务端对超出最大页的请求会把页码钳制到最后一页，
        // 返回与上一页完全相同的内容而不是空数组 —— 原实现会把这些
        // 重复条目无限追加（用户反馈：7 个结果被无限向下渲染）。
        // 现按 ID 去重：新页没有任何新条目即视为已到尽头，
        // 同时避免把重复条目塞进网格。
        final fresh = list
            .where((SearchAlbum a) => !_seenIds.contains(a.id))
            .toList();
        if (fresh.isEmpty) {
          _noMore = true;
        } else {
          for (final a in fresh) {
            _seenIds.add(a.id);
          }
          _items.addAll(fresh);
          _page++;
          _lastError = null;
        }
      }
    } catch (e) {
      // fetchPage 抛异常 → 记录真实错误并展示
      _lastError = e;
      _failed = _items.isEmpty;
      if (_items.isNotEmpty) _noMore = true;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  /// 外部刷新（排序切换、关键词变化等）。
  Future<void> reset() async {
    _items.clear();
    _seenIds.clear();
    _page = 1;
    _loading = false;
    _failed = false;
    _noMore = false;
    _lastError = null;
    if (mounted) setState(() {});
    _loadMore();
  }

  Future<void> retry() async {
    _failed = false;
    if (mounted) setState(() {});
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _loading) {
      return const LoadingView();
    }
    if (_items.isEmpty && _failed) {
      return ErrorView(error: _lastError, onRetry: retry);
    }
    if (_items.isEmpty && _noMore) {
      return const EmptyView(
        message: '没有找到相关内容',
        icon: Icons.manage_search_rounded,
      );
    }
    Widget grid = GridView.builder(
      // 关键修复（发现页滚动）：嵌套模式下不传 controller ——
      // NestedScrollView 会给 body 注入内部 PrimaryScrollController，
      // GridView 自动绑定后内滚到顶可继续滚外层 header（对齐官方
      // NestedScrollView 用法）；此前显式传入自有 controller 把内层
      // 位置从协调器里剥离，导致「最新上架」到顶后无法回顶、只能触发刷新。
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      // 性能：网格卡片无需保活；预滚动范围放宽减少滚动白块。
      // （cacheExtent 在 3.41 后被标记弃用但功能正常，且
      // ScrollCacheExtent 未被 material 导出，故继续使用。）
      // ignore: deprecated_member_use
      cacheExtent: 800,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.55,
      ),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          if (_failed) {
            return Center(
              child: IconButton.filledTonal(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded),
              ),
            );
          }
          // _noMore 时展示“已经到底啦”，否则展示加载圈。
          // 修复：此前 done 恒为 false，最后一页之后永远显示加载圈。
          return TailLoader(done: _noMore);
        }
        final a = _items[i];
        return AlbumCard(
          album: a,
          onTap: () => Navigator.pushNamed(context, '/album', arguments: a),
        );
      },
    );
    // 嵌套模式：自有 controller 未挂接，改用滚动通知检测触底。
    if (widget.usePrimaryScroll) {
      grid = NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: grid,
      );
    }
    // 嵌套模式关闭内部刷新：内层 overscroll 弹跳不再误触发刷新，
    // 到顶后的继续下拉交给外层 NestedScrollView 展开 header。
    if (!widget.enableRefresh) {
      return grid;
    }
    return RefreshIndicator(
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: reset,
      child: grid,
    );
  }
}
