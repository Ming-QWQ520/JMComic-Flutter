import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

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
      return _api.coverUrl(_album!.id.toString(),
          updateAt: _album!.updateAt);
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
      await _api.like({'aid': a.id.toString()});
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
        title: Text(_album?.name ?? _fallback?.name ?? '详情',
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
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : _buildBody(context, cs, tt),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final a = _album!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // ---------- 头部信息 ----------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Hero(
              tag: 'cover-${a.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 118,
                  height: 157,
                  child: _coverUrl.isEmpty
                      ? Container(color: cs.surfaceContainerHighest)
                      : CachedNetworkImage(
                          imageUrl: _coverUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 360,
                          errorWidget: (_, _, _) => Container(
                              color: cs.surfaceContainerHighest),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(a.name,
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('作者: ${a.authorText}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      _Stat(icon: Icons.visibility_outlined, label: '浏览', value: a.totalViews),
                      const SizedBox(width: 14),
                      _Stat(icon: Icons.favorite_rounded, label: '喜欢', value: a.totalLikes),
                      const SizedBox(width: 14),
                      _Stat(icon: Icons.auto_stories_outlined, label: '页数', value: '${a.totalPhotos}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      if (a.category.title.isNotEmpty)
                        Pill(label: a.category.title),
                      if (a.categorySub.title.isNotEmpty)
                        Pill(
                            label: a.categorySub.title,
                            color: cs.tertiary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        // ---------- 操作按钮 ----------
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _openReader(),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(a.series.isEmpty ? '开始阅读' : '从第一章开始'),
              ),
            ),
            const SizedBox(width: 10),
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
            const SizedBox(width: 10),
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
          ],
        ),
        // ---------- 简介 ----------
        if (a.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(title: '简介'),
          Text(a.description,
              style: tt.bodyMedium?.copyWith(height: 1.65)),
        ],
        // ---------- 标签 ----------
        if (a.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(title: '标签'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: a.tags
                .map((String t) => ActionChip(
                      label: Text(t),
                      labelStyle: TextStyle(fontSize: 12, color: cs.primary),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                          color: cs.primary.withValues(alpha: 0.35)),
                      onPressed: () => Navigator.pushNamed(
                          context, '/search',
                          arguments: t),
                    ))
                .toList(),
          ),
        ],
        // ---------- 章节 ----------
        if (a.series.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(title: '章节 (${a.series.length})'),
          ...a.series.map(
            (SeriesItem s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
                        color: cs.primary),
                  ),
                ),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant),
                onTap: () => _openReader(chapterId: s.id),
              ),
            ),
          ),
        ],
        // ---------- 系列作品 ----------
        if (a.works.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          SectionHeader(title: '系列作品'),
          ...a.works.map(
            (AlbumWorks w) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.collections_bookmark_outlined,
                    color: cs.primary),
                title: Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant),
                onTap: () => Navigator.pushReplacementNamed(
                    context, '/album',
                    arguments: w.id),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 统计小项。
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Text('$label $value',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
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
            Icon(icon,
                size: 20,
                color: active ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? cs.primary : cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
