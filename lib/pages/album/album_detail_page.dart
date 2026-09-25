import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../services/download_manager.dart';
import '../../services/image_store.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';
import 'album_comment_page.dart';

/// 漫画详情页。
///
/// 布局（优化后）：
/// - 头部：左侧 3:4 封面 + 右侧标题 / 作者 / 分类与编号信息；
/// - 统计区：浏览 / 喜欢 / 页数三分栏卡片，替代原先挤在一行的
///   小字图标，信息层级更清晰；
/// - 操作区：开始阅读主按钮 + 收藏 / 点赞 / 下载三个次级操作
///   （下载原先只藏在 AppBar，移动到操作区提升可发现性）；
/// - 简介 / 标签 / 章节 / 系列作品分区保持纵向流式排布。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final JmApi _api = JmApi.instance;
  Album? _album;
  bool _loading = true;
  String _error = '';
  String _id = '';
  SearchAlbum? _fallback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_id.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is SearchAlbum) {
        _fallback = args;
        _id = args.id;
      } else if (args is String) {
        _id = args;
      }
      _load();
    }
  }

  String get _coverUrl {
    if (_album != null) {
      return _api.coverUrl(_album!.id.toString(), updateAt: _album!.updateAt);
    }
    if (_fallback != null) {
      return JmApi.instance.coverUrl(_fallback!.id,
          updateAt: _fallback!.updateAt);
    }
    return '';
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的专辑 ID';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final a = await _api.getAlbum(_id);
      if (!mounted) return;
      setState(() {
        _album = a;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    final a = _album!;
    try {
      await _api.addFavorite(a.id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(a.isFavorite ? '已移出收藏' : '收藏成功')));
      setState(() => a.isFavorite = !a.isFavorite);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _toggleLike() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    final a = _album!;
    try {
      // 点赞（对齐 jmcomic APP API like 端点）
      await _api.miscPost('like', <String, dynamic>{
        'aid': a.id.toString(),
        'type': 'album',
        'action': a.liked ? 'unlike' : 'like',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(a.liked ? '已取消点赞' : '点赞成功')));
      setState(() => a.liked = !a.liked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  /// 下载整本（对齐 qt download_all_view）。
  Future<void> _downloadAll() async {
    final a = _album;
    if (a == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (a.series.isEmpty) {
        await DownloadManager.instance.addEps(
          albumId: a.id.toString(),
          albumName: a.name,
          epsId: a.id.toString(),
          epsName: a.name,
        );
      } else {
        await DownloadManager.instance.addAlbum(
          albumId: a.id.toString(),
          albumName: a.name,
          series: a.series,
        );
      }
      messenger.showSnackBar(const SnackBar(content: Text('已加入下载队列')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('加入下载失败: $e')));
    }
  }

  void _needLogin() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先登录')));
    Navigator.pushNamed(context, '/login');
  }

  void _openReader({String chapterId = ''}) {
    Navigator.pushNamed(
      context,
      '/reader',
      arguments: <String, String>{
        'albumId': _album!.id.toString(),
        'chapterId': chapterId.isEmpty ? _album!.id.toString() : chapterId,
        'title': _album!.name,
      },
    );
  }

  void _openComments() {
    final a = _album!;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            AlbumCommentPage(albumId: a.id.toString(), albumName: a.name),
      ),
    );
  }

  Future<void> _buyWithCoin() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    try {
      await _api.buyComicWithCoin(_album!.id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('购买成功')));
      // 同步刷新：重载专辑详情（已购状态/内容立即生效），
      // 并拉取最新用户资料（J币余额即时更新）。
      context.read<AppState>().refreshUser();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('购买失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _album?.name ?? _fallback?.name ?? '详情',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '评论',
            icon: const Icon(Icons.comment_outlined),
            onPressed: _album == null ? null : _openComments,
          ),
          IconButton(
            tooltip: 'J 币购买',
            icon: const Icon(Icons.monetization_on_outlined),
            onPressed: _album == null ? null : _buyWithCoin,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
          ? ErrorView(message: _error, onRetry: _load)
          : _buildBody(context, cs, tt),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final a = _album!;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        // ---------- 头部横幅（JM 官方风格：模糊封面背景 + 信息叠加） ----------
        _HeaderBanner(
          coverUrl: _coverUrl,
          title: a.name,
          author: a.authorText,
          pills: <String>[
            if (a.category.title.isNotEmpty) a.category.title,
            if (a.categorySub.title.isNotEmpty) a.categorySub.title,
          ],
          albumId: a.id,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ---------- 统计区（三分栏卡片） ----------
              _StatsBar(
                views: a.totalViews,
                likes: a.totalLikes,
                photos: '${a.totalPhotos}',
              ),
              // ---------- 操作按钮 ----------
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => _openReader(),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(a.series.isEmpty ? '开始阅读' : '从第一章开始'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RoundAction(
                      icon: a.isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      label: a.isFavorite ? '已收藏' : '收藏',
                      active: a.isFavorite,
                      onTap: _toggleFavorite,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RoundAction(
                      icon: a.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: a.liked ? '已赞' : '点赞',
                      active: a.liked,
                      onTap: _toggleLike,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RoundAction(
                      icon: Icons.download_rounded,
                      label: '下载',
                      active: false,
                      onTap: _downloadAll,
                    ),
                  ),
                ],
              ),
              // ---------- 简介 ----------
              if (a.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                SectionHeader(title: '简介'),
                Text(
                  stripHtmlTags(a.description),
                  style: tt.bodyMedium?.copyWith(height: 1.65),
                ),
              ],
              // ---------- 标签 ----------
              if (a.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                SectionHeader(title: '标签'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: a.tags
                      .map(
                        (String t) => ActionChip(
                          label: Text(t),
                          labelStyle:
                              TextStyle(fontSize: 12, color: cs.primary),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                              color: cs.primary.withValues(alpha: 0.35)),
                          onPressed: () => Navigator.pushNamed(
                              context, '/search',
                              arguments: t),
                        ),
                      )
                      .toList(),
                ),
              ],
              // ---------- 章节 ----------
              if (a.series.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                SectionHeader(title: '章节 (${a.series.length})'),
                ...a.series.map(
                  (SeriesItem s) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      leading: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          s.sort,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => _openReader(chapterId: s.id),
                    ),
                  ),
                ),
              ],
              // ---------- 系列作品 ----------
              if (a.works.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                SectionHeader(title: '系列作品'),
                ...a.works.map(
                  (AlbumWorks w) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.collections_bookmark_outlined,
                        color: cs.primary,
                      ),
                      title: Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => Navigator.pushReplacementNamed(
                        context,
                        '/album',
                        arguments: w.id,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 详情页头部横幅（JM 官方风格）：
/// 封面高斯模糊铺满作为背景 + 深色渐变遮罩，前景叠加
/// 封面原图 / 标题 / 作者 / 分类胶囊 / 编号。
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.coverUrl,
    required this.title,
    required this.author,
    required this.pills,
    required this.albumId,
  });

  final String coverUrl;
  final String title;
  final String author;
  final List<String> pills;
  final int albumId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return RepaintBoundary(
      child: Stack(
        children: <Widget>[
          // 背景层：封面模糊铺满（RepaintBoundary 限制重绘范围）
          Positioned.fill(
            child: coverUrl.isEmpty
                ? ColoredBox(color: cs.surfaceContainerHighest)
                : ClipRect(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: 16,
                        sigmaY: 16,
                        tileMode: TileMode.decal,
                      ),
                      child: Transform.scale(
                        scale: 1.15,
                        child: ImageStoreCover(
                          url: coverUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
          ),
          // 遮罩层：保证前景文字可读
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
          ),
          // 前景：封面 + 信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Hero(
                  tag: 'cover-$albumId',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 118,
                        height: 157, // 3:4
                        child: coverUrl.isEmpty
                            ? Container(color: cs.surfaceContainerHighest)
                            : ImageStoreCover(url: coverUrl),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.25,
                          shadows: const <Shadow>[
                            Shadow(blurRadius: 6, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                      if (pills.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: pills
                              .map(
                                (String p) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    p,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '编号 #$albumId',
                        style: tt.labelSmall?.copyWith(
                          color: Colors.white60,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情页封面（走 ImageStore 统一加载，含 `_3x4` 回退与魔数校验）。
class ImageStoreCover extends StatefulWidget {
  const ImageStoreCover({super.key, required this.url, this.fit});

  final String url;
  final BoxFit? fit;

  @override
  State<ImageStoreCover> createState() => _ImageStoreCoverState();
}

class _ImageStoreCoverState extends State<ImageStoreCover> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = ImageStore.instance.load(widget.url);
  }

  @override
  void didUpdateWidget(ImageStoreCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = ImageStore.instance.load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (BuildContext c, AsyncSnapshot<Uint8List?> snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: snap.connectionState == ConnectionState.waiting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.broken_image_outlined, color: cs.outline),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit ?? BoxFit.cover,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// 统计条：浏览 / 喜欢 / 页数三分栏。
class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.views,
    required this.likes,
    required this.photos,
  });

  final String views;
  final String likes;
  final String photos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StatCell(
              icon: Icons.visibility_outlined,
              label: '浏览',
              value: views,
            ),
          ),
          Container(width: 1, height: 26, color: cs.outlineVariant),
          Expanded(
            child: _StatCell(
              icon: Icons.favorite_rounded,
              label: '喜欢',
              value: likes,
            ),
          ),
          Container(width: 1, height: 26, color: cs.outlineVariant),
          Expanded(
            child: _StatCell(
              icon: Icons.auto_stories_outlined,
              label: '页数',
              value: photos,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个统计格。
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: cs.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 圆形操作按钮。
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
