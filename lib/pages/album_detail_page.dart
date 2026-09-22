import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../api/jm_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';

/// 漫画详情页。
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_id.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      _id = args is SearchAlbum
          ? args.id
          : args is String
              ? args
              : '';
      _load();
    }
  }

  String get _coverUrl {
    if (_album == null) return '';
    return _api.coverUrl(_album!.id.toString(), updateAt: _album!.updateAt);
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的专辑 ID';
      });
      return;
    }
    try {
      final a = await _api.getAlbum(_id);
      if (!mounted) return;
      setState(() {
        _album = a;
        _loading = false;
      });
      // 上报浏览历史（登录后）
      final app = context.read<AppState>();
      if (app.isLogged) {
        try {
          await _api.updateWatchList(_id);
        } catch (_) {}
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(a.isFavorite ? '已移出收藏' : '收藏成功')),
      );
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
      await _api.like(<String, dynamic>{'aid': a.id.toString()});
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

  Future<void> _toggleTrack() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    try {
      await _api.sertrackPost(_album!.id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('追更状态已切换')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  void _needLogin() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先登录')),
    );
    Navigator.pushNamed(context, '/login');
  }

  void _openReader({String chapterId = ''}) {
    Navigator.pushNamed(context, '/reader', arguments: <String, String>{
      'albumId': _album!.id.toString(),
      'chapterId': chapterId.isEmpty ? _album!.id.toString() : chapterId,
      'title': _album!.name,
    });
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('购买失败: $e')));
    }
  }

  Future<void> _showDownloadInfo() async {
    try {
      final data = await _api.getAlbumDownload(_album!.id.toString());
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('下载包信息'),
          content: SingleChildScrollView(child: Text(data?.toString() ?? '无')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('获取失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.name ?? '详情',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: '追更',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: _album == null ? null : _toggleTrack,
          ),
          IconButton(
            tooltip: '下载包信息',
            icon: const Icon(Icons.download_outlined),
            onPressed: _album == null ? null : _showDownloadInfo,
          ),
          IconButton(
            tooltip: 'J 币购买',
            icon: const Icon(Icons.monetization_on_outlined),
            onPressed: _album == null ? null : _buyWithCoin,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_error, textAlign: TextAlign.center),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _buildBody(context, cs, tt),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final a = _album!;
    final cover = _coverUrl;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 160,
                child: cover.isEmpty
                    ? Container(color: cs.surfaceContainerHighest)
                    : CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(color: cs.surfaceContainerHighest),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(a.name, style: tt.titleMedium),
                  const SizedBox(height: 6),
                  Text('作者: ${a.authorText}',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    '浏览 ${a.totalViews} · 喜欢 ${a.totalLikes} · ${a.totalPhotos} 页',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      if (a.category.title.isNotEmpty)
                        Chip(
                          label: Text(a.category.title,
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (a.categorySub.title.isNotEmpty)
                        Chip(
                          label: Text(a.categorySub.title,
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openReader(),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(a.series.isEmpty ? '开始阅读' : '从第一章开始'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: a.isFavorite ? '已收藏' : '收藏',
              onPressed: _toggleFavorite,
              icon: Icon(
                a.isFavorite
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: a.liked ? '已点赞' : '点赞',
              onPressed: _toggleLike,
              icon: Icon(
                a.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              ),
            ),
          ],
        ),
        if (a.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('简介', style: tt.titleSmall),
          const SizedBox(height: 6),
          Text(a.description, style: tt.bodyMedium),
        ],
        if (a.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('标签', style: tt.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: a.tags
                .map((String t) => ActionChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pushNamed(context, '/search',
                          arguments: t),
                    ))
                .toList(),
          ),
        ],
        if (a.series.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('章节 (${a.series.length})', style: tt.titleSmall),
          const SizedBox(height: 6),
          ...a.series.map(
            (SeriesItem s) => Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: Text(s.sort, style: tt.labelLarge),
                title: Text(s.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openReader(chapterId: s.id),
              ),
            ),
          ),
        ],
        if (a.works.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('系列作品', style: tt.titleSmall),
          const SizedBox(height: 6),
          ...a.works.map(
            (AlbumWorks w) => Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                title: Text(w.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pushReplacementNamed(
                    context, '/album',
                    arguments: w.id),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
