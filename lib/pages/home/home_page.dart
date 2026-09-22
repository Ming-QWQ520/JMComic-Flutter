import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';

/// 发现页：热门标签 + 最新漫画无限流。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  late final AlbumGrid _grid;
  List<String> _hotTags = <String>[];
  bool _tagsLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _grid = AlbumGrid(
      fetchPage: (int page) async {
        try {
          return await JmApi.instance.getLatest(page);
        } catch (_) {
          return null;
        }
      },
    );
    _loadHotTags();
  }

  Future<void> _loadHotTags() async {
    try {
      final data = await JmApi.instance.getHotTags();
      final tags = <String>[];
      void walk(dynamic v) {
        if (v is List) {
          for (final item in v) {
            walk(item);
          }
        } else if (v is Map) {
          final name = v['name'] ?? v['tag'];
          if (name is String && name.isNotEmpty) tags.add(name);
          v.forEach((_, dynamic value) {
            if (value is List || value is Map) walk(value);
          });
        }
      }

      walk(data);
      if (!mounted) return;
      setState(() {
        _hotTags = tags.take(24).toList();
        _tagsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _tagsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!state.ready) {
      return const Scaffold(body: LoadingView(message: '正在解析服务器线路…'));
    }
    if (state.initError != null) {
      return Scaffold(
        body: ErrorView(
          message: '主机解析失败：${state.initError}',
          onRetry: () => state.init(),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 118,
            collapsedHeight: 64,
            toolbarHeight: 64,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
              centerTitle: false,
              title: Text('发现',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primary.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '每周更新',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () => Navigator.pushNamed(context, '/week'),
              ),
              IconButton(
                tooltip: '随机一部',
                icon: const Icon(Icons.casino_outlined),
                onPressed: _openRandom,
              ),
              const SizedBox(width: 6),
            ],
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: _tagsLoading
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _hotTags.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final t = _hotTags[i];
                        return ActionChip(
                          label: Text(t),
                          labelStyle: const TextStyle(fontSize: 12.5),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.6),
                          ),
                          onPressed: () => Navigator.pushNamed(
                              context, '/search',
                              arguments: t),
                        );
                      },
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: SectionHeader(title: '最新上架'),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: _grid,
          ),
        ],
      ),
    );
  }

  Future<void> _openRandom() async {
    try {
      final data = await JmApi.instance.getRandomRecommend();
      final list = SearchAlbum.listFrom(data);
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('随机推荐为空')));
        return;
      }
      Navigator.pushNamed(context, '/album', arguments: list.first);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('随机推荐加载失败')));
    }
  }
}
