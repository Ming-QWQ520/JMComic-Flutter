import 'package:flutter/material.dart';

import '../core/protocol/models.dart';
import 'album_card.dart';
import 'feedback.dart';

/// 无限滚动专辑网格（最新/搜索/分类/收藏/历史等复用）。
class AlbumGrid extends StatefulWidget {
  const AlbumGrid({
    super.key,
    required this.fetchPage,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  /// 返回 null 表示失败；空数组表示没有更多。
  final Future<List<SearchAlbum>?> Function(int page) fetchPage;
  final EdgeInsetsGeometry padding;

  @override
  State<AlbumGrid> createState() => AlbumGridState();
}

class AlbumGridState extends State<AlbumGrid> {
  final List<SearchAlbum> _items = <SearchAlbum>[];
  final ScrollController _scroll = ScrollController();

  int _page = 1;
  bool _loading = false;
  bool _failed = false;
  bool _noMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 700) {
      _loadMore();
    }
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
        if (list.isEmpty) _noMore = true;
        _items.addAll(list);
        _page++;
      }
    } catch (_) {
      _failed = _items.isEmpty;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  /// 外部刷新（排序切换、关键词变化等）。
  Future<void> reset() async {
    _items.clear();
    _page = 1;
    _loading = false;
    _failed = false;
    _noMore = false;
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
      return ErrorView(onRetry: retry);
    }
    if (_items.isEmpty && _noMore) {
      return const EmptyView(message: '没有找到相关内容', icon: Icons.manage_search_rounded);
    }
    return RefreshIndicator(
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: reset,
      child: GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        itemCount: _items.length + (_noMore ? 1 : 1),
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
            return const TailLoader();
          }
          final a = _items[i];
          return AlbumCard(
            album: a,
            onTap: () =>
                Navigator.pushNamed(context, '/album', arguments: a),
          );
        },
      ),
    );
  }
}
