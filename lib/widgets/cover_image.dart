import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/protocol/jm_api.dart';
import '../core/protocol/jm_client.dart';
import '../core/protocol/models.dart';
import '../services/image_store.dart';

/// 封面图片（统一走 ImageStore：魔数校验 + `_3x4` 回退 + 双缓存）。
///
/// 修复：旧实现使用 CachedNetworkImage，当 CDN 被 WAF 拦截返回
/// 200 + HTML 反爬页、或 `_3x4` 封面变体缺失返回错误页时，坏字节
/// 直接交给解码器，反复输出 Failed to decode image 日志。现在统一
/// 经 [ImageStore] 加载（内部调用带魔数校验的 fetchImage），坏响应
/// 会被识别为失败并自动换线路重试，不再污染解码器。
class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.album, this.fit});

  final SearchAlbum album;
  final BoxFit? fit;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  String _url = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 专辑变化（网格复用）时重新解析封面地址。
    if (oldWidget.album.id != widget.album.id ||
        oldWidget.album.image != widget.album.image ||
        oldWidget.album.updateAt != widget.album.updateAt) {
      _start();
    }
  }

  void _start() {
    _url = resolveCoverUrl(widget.album);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StoreImage(
      url: _url,
      fit: widget.fit ?? BoxFit.cover,
      placeholder: (BuildContext c) => Container(
        color: cs.surfaceContainerHighest,
      ),
      error: (BuildContext c) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: cs.outline,
        ),
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

/// 用户头像（评论等场景）。
///
/// 修复：旧实现用裸 NetworkImage（不带 UA 头），Dart 默认 UA 易被
/// CDN/WAF 拦截并返回反爬页，产生解码失败日志；现统一走 ImageStore。
class AvatarImage extends StatefulWidget {
  const AvatarImage({super.key, required this.photo, this.radius = 16});

  /// 头像相对路径（photo 字段；空 / nopic-* 时使用默认头像）。
  final String photo;
  final double radius;

  @override
  State<AvatarImage> createState() => _AvatarImageState();
}

class _AvatarImageState extends State<AvatarImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _start();
  }

  void _start() {
    final url = JmApi.instance.avatarUrl(widget.photo);
    _future = url.isEmpty
        ? Future<Uint8List?>.value(null)
        : ImageStore.instance.load(url);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: cs.primary.withValues(alpha: 0.12),
      child: ClipOval(
        child: SizedBox(
          width: widget.radius * 2,
          height: widget.radius * 2,
          child: FutureBuilder<Uint8List?>(
            future: _future,
            builder: (BuildContext c, AsyncSnapshot<Uint8List?> snap) {
              final bytes = snap.data;
              if (bytes == null || bytes.isEmpty) {
                return Icon(
                  Icons.person_rounded,
                  size: widget.radius,
                  color: cs.primary,
                );
              }
              return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
        ),
      ),
    );
  }
}
