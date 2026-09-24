import 'package:flutter/material.dart';

import '../core/protocol/models.dart';
import 'cover_image.dart';

/// 专辑封面卡片（网格用）：圆角封面 + 分类角标 + 标题 + 作者。
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.album, this.onTap});

  final SearchAlbum album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final badge = album.categorySub.title.isNotEmpty
        ? album.categorySub.title
        : album.category.title;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      // 关键修复：onTap 为空时默认跳转详情页。此前首页横滑分区
      // 未传 onTap，InkWell 收到 null 直接吞掉点击，表现为
      // "首页无法点击观看漫画"。
      onTap:
          onTap ??
          () => Navigator.pushNamed(context, '/album', arguments: album),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: cs.surfaceContainerHighest,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CoverImage(album: album),
                  ),
                ),
                // 底部渐变遮罩
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                if (badge.isNotEmpty)
                  Positioned(left: 8, top: 8, child: _Badge(label: badge)),
                if (album.liked || album.isFavorite)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Icon(
                      album.liked
                          ? Icons.favorite_rounded
                          : Icons.bookmark_rounded,
                      size: 15,
                      color: album.liked
                          ? const Color(0xFFFF6B9D)
                          : const Color(0xFF7CDBFF),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            album.author.isEmpty ? 'ID ${album.id}' : album.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
