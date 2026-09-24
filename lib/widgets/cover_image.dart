import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/protocol/jm_api.dart';
import '../core/protocol/jm_client.dart';
import '../core/protocol/models.dart';

/// 封面图片（含缓存、占位与多级 URL 解析）。
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.album, this.fit});

  final SearchAlbum album;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final url = resolveCoverUrl(album);
    if (url.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      // 与原生图片下载相同的请求头（UA 等），避免 CDN/WAF 拦截
      // Dart 默认 UA 返回反爬网页导致图片解码失败。
      httpHeaders: JmClient.instance.imgHttpHeaders,
      fit: fit ?? BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      memCacheWidth: 480,
      placeholder: (_, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (_, _, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

/// 封面地址解析：优先完整 URL，其次 img_host + 规范路径。
String resolveCoverUrl(SearchAlbum album) {
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
