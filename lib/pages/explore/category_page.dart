import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';

/// 分类页：分类入口列表。
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  final JmApi _api = JmApi.instance;
  List<Category> _cats = <Category>[];
  bool _loading = true;
  String _error = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getCategories();
      if (!mounted) return;
      setState(() {
        _cats = data.categories;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (!state.ready) {
      return const Scaffold(body: LoadingView());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类'),
        actions: [
          IconButton(
            tooltip: '重新加载',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          // 右上角搜索入口，与首页保持一致。
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
          ? ErrorView(message: _error, onRetry: _load)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _cats.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final cat = _cats[i];
                return Card(
                  child: InkWell(
                    onTap: () => _openCategory(context, cat),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconFor(cat),
                              size: 22,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.name,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _subTitle(cat),
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// 副标题：服务端部分分类不下发总数（total_albums 为空 / 0），
  /// 但内容实际存在 —— 此时显示引导文案而不是误导性的"共 0 部作品"。
  String _subTitle(Category cat) {
    final hasSub = cat.subCategories.isNotEmpty;
    if (!cat.hasTotal) {
      return hasSub ? '${cat.subCategories.length} 个子分类 · 点击浏览作品' : '点击浏览作品';
    }
    return hasSub
        ? '${cat.subCategories.length} 个子分类 · 共 ${cat.totalAlbums} 部作品'
        : '共 ${cat.totalAlbums} 部作品';
  }

  IconData _iconFor(Category cat) {
    final slug = cat.slug.toLowerCase();
    const map = <String, IconData>{
      'doujin': Icons.groups_rounded,
      'single': Icons.person_rounded,
      'ganbaru': Icons.fitness_center_rounded,
      'cg': Icons.palette_rounded,
      'haniman': Icons.menu_book_rounded,
      'short': Icons.timer_rounded,
      'complete': Icons.check_circle_outline_rounded,
    };
    return map[slug] ?? Icons.auto_awesome_rounded;
  }

  void _openCategory(BuildContext context, Category cat) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => CategoryListPage(category: cat)),
    );
  }
}

/// 分类筛选排序列表页。
class CategoryListPage extends StatefulWidget {
  const CategoryListPage({super.key, required this.category});

  final Category category;

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  String _sub = '';
  String _order = 'mr';

  /// 排序（对齐 qt GetSearchCategoryReq2：o = mr/mv/mv_m/mv_w/mv_t/mp/tf）。
  static const Map<String, String> _orders = <String, String>{
    'mr': '最新',
    'mv': '总点击',
    'mv_m': '月点击',
    'mv_w': '周点击',
    'mv_t': '日点击',
    'mp': '最多图片',
    'tf': '最多爱心',
  };

  final GlobalKey<AlbumGridState> _gridKey = GlobalKey<AlbumGridState>();

  void _resetGrid() => _gridKey.currentState?.reset();

  Future<List<SearchAlbum>?> _fetch(int page) async {
    // 对齐 qt GetSearchCategoryReq2：c=分类 slug，o=排序
    // 异常直接抛给 AlbumGrid，展示真实错误详情
    final r = await JmApi.instance.searchCategory(
      _sub.isEmpty ? widget.category.slug : _sub,
      page,
      order: _order,
    );
    return r.content;
  }

  @override
  Widget build(BuildContext context) {
    final subs = widget.category.subCategories;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (String v) {
              setState(() => _order = v);
              _resetGrid();
            },
            itemBuilder: (_) => _orders.entries
                .map(
                  (MapEntry<String, String> e) => PopupMenuItem<String>(
                    value: e.key,
                    child: Row(
                      children: [
                        if (_order == e.key)
                          Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(e.value),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (subs.isNotEmpty)
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _sub.isEmpty,
                      onSelected: (_) {
                        setState(() => _sub = '');
                        _resetGrid();
                      },
                    ),
                  ),
                  ...subs.map(
                    (SubCategory s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.name),
                        selected: _sub == s.slug,
                        onSelected: (_) {
                          setState(() => _sub = s.slug);
                          _resetGrid();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: AlbumGrid(key: _gridKey, fetchPage: _fetch),
          ),
        ],
      ),
    );
  }
}
