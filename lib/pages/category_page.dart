import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/jm_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 分类页：分类列表 + 子分类筛选。
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final JmApi _api = JmApi.instance;
  List<Category> _cats = <Category>[];
  bool _loading = true;
  String _error = '';

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
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('分类')),
      body: !state.ready
          ? const Center(child: CircularProgressIndicator())
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? ErrorBox(message: _error, onRetry: _load)
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _cats.length,
                      itemBuilder: (BuildContext c, int i) {
                        final cat = _cats[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: ListTile(
                            title: Text(cat.name),
                            subtitle: cat.subCategories.isEmpty
                                ? null
                                : Text(
                                    '子分类 ${cat.subCategories.length} 个 · 共 ${cat.totalAlbums} 部',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openCategory(context, cat),
                          ),
                        );
                      },
                    ),
    );
  }

  void _openCategory(BuildContext context, Category cat) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryListPage(category: cat),
      ),
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

  static const Map<String, String> _orders = <String, String>{
    'mr': '最新',
    'mt': '最多浏览',
    'tf': '最多喜欢',
    't': '最新发布',
  };

  final GlobalKey<AlbumGridState> _gridKey = GlobalKey<AlbumGridState>();

  void _resetGrid() => _gridKey.currentState?.reset();

  Future<List<SearchAlbum>?> _fetch(int page) async {
    try {
      return await JmApi.instance.getCategoriesFilter(
        categorySub: _sub.isEmpty ? widget.category.slug : _sub,
        page: page,
        order: _order,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = widget.category.subCategories;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: <Widget>[
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            onSelected: (String v) {
              setState(() => _order = v);
              _resetGrid();
            },
            itemBuilder: (_) => _orders.entries
                .map((MapEntry<String, String> e) => PopupMenuItem<String>(
                      value: e.key,
                      child:
                          Text(_order == e.key ? '${e.value} ✓' : e.value),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (subs.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(6),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(4),
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
                      padding: const EdgeInsets.all(4),
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
            child: AlbumGrid(
              key: _gridKey,
              fetchPage: _fetch,
            ),
          ),
        ],
      ),
    );
  }
}
