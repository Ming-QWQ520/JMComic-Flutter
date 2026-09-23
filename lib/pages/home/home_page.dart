import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_card.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';

/// 首页（对齐 qt IndexView）：promote 分区横滑 + 最新漫画无限流。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  late final AlbumGrid _grid;
  List<IndexBlock> _blocks = <IndexBlock>[];
  bool _blocksLoading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _grid = AlbumGrid(
      // 异常直接抛给 AlbumGrid，展示真实错误详情
      fetchPage: (int page) => JmApi.instance.getLatest(page),
    );
    _loadBlocks();
  }

  Future<void> _loadBlocks() async {
    try {
      final blocks = await JmApi.instance.getPromote();
      if (!mounted) return;
      setState(() {
        _blocks = blocks.where((b) => b.bookList.isNotEmpty).toList();
        _blocksLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _blocksLoading = false);
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
              title: Text(
                '首页',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
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
          // promote 分区（对齐 qt IndexView 分区横滑）
          for (final block in _blocks) ...<Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: SectionHeader(title: block.title),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 218,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: block.bookList.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(
                    width: 118,
                    child: AlbumCard(album: block.bookList[i]),
                  ),
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: SectionHeader(title: '最新上架'),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: _blocksLoading ? const SizedBox.shrink() : _grid,
          ),
        ],
      ),
    );
  }

  Future<void> _openRandom() async {
    try {
      final list = await JmApi.instance.getRandomRecommend();
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
