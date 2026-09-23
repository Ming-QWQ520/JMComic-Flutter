import 'package:flutter/material.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../widgets/album_card.dart';
import '../../widgets/feedback.dart';

/// 收藏页（对齐 qt FavoriteView / FavoriteFoldView）。
///
/// - GET favorite?page=&folder_id=&o= 分页加载（mr 收藏时间 / mp 更新时间）；
/// - 响应中的 folder_list 驱动收藏夹切换；
/// - POST favorite_folder 新建/删除收藏夹。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final JmApi _api = JmApi.instance;
  final ScrollController _scroll = ScrollController();

  final List<SearchAlbum> _items = <SearchAlbum>[];
  final List<FavoriteFolder> _folders = <FavoriteFolder>[];
  String _fid = '0';
  String _order = 'mr';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getFavoriteList(page: 1, order: _order, fid: _fid);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(data.bookList);
        _total = data.total;
        _folders
          ..clear()
          ..addAll(data.folders);
        _page = 1;
        _noMore = _items.length >= _total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _loading) return;
    _loadingMore = true;
    try {
      final data =
          await _api.getFavoriteList(page: _page + 1, order: _order, fid: _fid);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(data.bookList);
        _noMore = _items.length >= _total;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  /// 新建收藏夹（对齐 AddFavoritesFoldReq2）。
  Future<void> _addFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '收藏夹名称'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _api.addFavoriteFolder(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已创建「$name」')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  /// 删除收藏夹（对齐 DelFavoritesFoldReq2）。
  Future<void> _delFolder(FavoriteFolder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('确定删除「${f.name}」吗？其中的漫画将回到默认收藏。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delFavoriteFolder(f.fid);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除')));
      if (_fid == f.fid) _fid = '0';
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (String v) {
              setState(() => _order = v);
              _load();
            },
            itemBuilder: (_) => const <PopupMenuItem<String>>[
              PopupMenuItem<String>(value: 'mr', child: Text('按收藏时间')),
              PopupMenuItem<String>(value: 'mp', child: Text('按更新时间')),
            ],
          ),
          IconButton(
            tooltip: '新建收藏夹',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _addFolder,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 收藏夹切换条
          if (_folders.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('默认收藏'),
                      selected: _fid == '0',
                      onSelected: (_) {
                        setState(() => _fid = '0');
                        _load();
                      },
                    ),
                  ),
                  ..._folders.map(
                    (FavoriteFolder f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(f.name),
                        selected: _fid == f.fid,
                        onSelected: (_) {
                          setState(() => _fid = f.fid);
                          _load();
                        },
                        onDeleted: () => _delFolder(f),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error.isNotEmpty
                    ? ErrorView(message: _error, onRetry: _load)
                    : _items.isEmpty
                        ? const EmptyView(message: '暂无收藏')
                        : GridView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 160,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.55,
                            ),
                            itemCount:
                                _items.length + (_noMore ? 0 : 1),
                            itemBuilder: (_, i) {
                              if (i >= _items.length) {
                                return const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2));
                              }
                              final a = _items[i];
                              return AlbumCard(
                                album: a,
                                onTap: () => Navigator.pushNamed(
                                    context, '/album',
                                    arguments: a),
                              );
                            },
                          ),
          ),
          // 统计条
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.folder_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$_total 个收藏 · ${_folders.length} 个收藏夹',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 浏览历史页（对齐 qt HistoryView / GetHistoryReq2）。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final JmApi _api = JmApi.instance;
  final ScrollController _scroll = ScrollController();
  final List<SearchAlbum> _items = <SearchAlbum>[];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await _api.getWatchList(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _page = 1;
        _noMore = list.isEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _loading) return;
    _loadingMore = true;
    try {
      final list = await _api.getWatchList(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(list);
        _noMore = list.isEmpty;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('浏览历史')),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(message: '暂无浏览记录')
                  : GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.55,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        return AlbumCard(
                          album: a,
                          onTap: () => Navigator.pushNamed(
                              context, '/album',
                              arguments: a),
                        );
                      },
                    ),
    );
  }
}
