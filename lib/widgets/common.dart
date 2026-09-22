import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/jm_api.dart';
import '../api/jm_client.dart';
import '../api/models.dart';

/// 统一错误提示组件。
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              message ?? '加载失败，请检查网络后重试',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空列表占位。
class EmptyBox extends StatelessWidget {
  const EmptyBox({super.key, this.message = '暂无内容'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 封面图片（含缓存与占位）。
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.album, this.fit});

  final SearchAlbum album;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final url = _resolveUrl();
    if (url.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_rounded),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit ?? BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorWidget: (_, _, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded),
      ),
    );
  }

  /// 封面地址解析：优先绝对 URL，其次 img_host + 拼接规则。
  String _resolveUrl() {
    final img = album.image;
    if (img.startsWith('http')) return img;
    final direct = JmApi.instance.coverUrl(album.id, updateAt: album.updateAt);
    if (direct.isNotEmpty) return direct;
    if (img.isNotEmpty) {
      final host = JmClient.instance.imgHost;
      if (host.isNotEmpty) {
        final slash = host.endsWith('/') ? '' : '/';
        var path = img;
        if (!path.startsWith('media/')) path = 'media/albums/$path';
        return '$host$slash$path';
      }
    }
    return '';
  }
}

/// 专辑卡片（网格用）。
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, this.onTap});

  final SearchAlbum album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(album: album),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        album.categorySub.title.isNotEmpty
                            ? album.categorySub.title
                            : album.category.title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (album.liked)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.favorite_rounded,
                              size: 12, color: cs.primary),
                        ),
                      if (album.isFavorite)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.bookmark_rounded,
                              size: 12, color: cs.tertiary),
                        ),
                      Expanded(
                        child: Text(
                          album.author.isEmpty ? album.id : album.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 无限滚动专辑网格（最新/搜索/分类/收藏/历史等复用）。
class AlbumGrid extends StatefulWidget {
  const AlbumGrid({
    super.key,
    required this.fetchPage,
    this.padding = const EdgeInsets.all(8),
  });

  /// 返回 null 表示失败；空数组表示没有更多。
  final Future<List<SearchAlbum>?> Function(int page) fetchPage;
  final EdgeInsetsGeometry padding;

  @override
  AlbumGridState createState() => AlbumGridState();
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
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
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
        _failed = true;
      } else {
        if (list.isEmpty) _noMore = true;
        _items.addAll(list);
        _page++;
      }
    } catch (_) {
      _failed = true;
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _failed) {
      return ErrorBox(onRetry: retry);
    }
    if (_items.isEmpty && _noMore) {
      return const EmptyBox();
    }
    return RefreshIndicator(
      onRefresh: reset,
      child: GridView.builder(
        controller: _scroll,
        padding: widget.padding,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.52,
        ),
        itemCount: _items.length + (_noMore ? 0 : 1),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            if (_failed) {
              return Center(
                child: IconButton(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              );
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final a = _items[i];
          return AlbumCard(
            album: a,
            onTap: () => Navigator.pushNamed(context, '/album', arguments: a),
          );
        },
      ),
    );
  }
}
