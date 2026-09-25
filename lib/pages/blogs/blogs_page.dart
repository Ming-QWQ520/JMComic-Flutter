import 'package:flutter/material.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../widgets/feedback.dart';

/// 深夜食堂页（对齐 qt GetBlogsReq2 / GetBlogInfoReq2 / GetBlogForumReq2）。
///
/// 支持按分类浏览（dinner 等）、搜索、分页，详情为文本内容。
class BlogsPage extends StatefulWidget {
  const BlogsPage({super.key});

  @override
  State<BlogsPage> createState() => _BlogsPageState();
}

class _BlogsPageState extends State<BlogsPage> {
  final JmApi _api = JmApi.instance;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  String _blogType = 'dinner';
  String _searchQuery = '';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String _error = '';

  static const Map<String, String> _blogTypes = <String, String>{
    'dinner': '深夜食堂',
  };

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
    _searchCtrl.dispose();
    super.dispose();
  }

  dynamic _listOf(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final k in const <String>['list', 'content', 'blogs', 'data']) {
        if (data[k] is List) return data[k];
      }
    }
    return const <dynamic>[];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getBlogs(
        blogType: _blogType,
        searchQuery: _searchQuery,
      );
      if (!mounted) return;
      final list = _listOf(data);
      setState(() {
        _items
          ..clear()
          ..addAll(_normalize(list));
        _page = 1;
        _noMore = list.isEmpty;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _loading) return;
    _loadingMore = true;
    try {
      final data = await _api.getBlogs(
        blogType: _blogType,
        searchQuery: _searchQuery,
        page: _page + 1,
      );
      if (!mounted) return;
      final list = _listOf(data);
      setState(() {
        _page += 1;
        _items.addAll(_normalize(list));
        _noMore = list.isEmpty;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  List<Map<String, dynamic>> _normalize(dynamic list) {
    final out = <Map<String, dynamic>>[];
    if (list is List) {
      for (final v in list) {
        if (v is Map<String, dynamic>) out.add(v);
      }
    }
    return out;
  }

  String _titleOf(Map<String, dynamic> m) =>
      (m['title'] ?? m['name'] ?? m['blog_title'] ?? '无标题').toString();

  String _idOf(Map<String, dynamic> m) =>
      (m['id'] ?? m['blog_id'] ?? m['BID'] ?? '').toString();

  String _subOf(Map<String, dynamic> m) =>
      (m['description'] ?? m['sub_title'] ?? m['addtime'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('深夜食堂'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '分类',
            icon: const Icon(Icons.category_outlined),
            onSelected: (String v) {
              setState(() => _blogType = v);
              _load();
            },
            itemBuilder: (_) => _blogTypes.entries
                .map((MapEntry<String, String> e) => PopupMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (String v) {
                _searchQuery = v.trim();
                _load();
              },
              decoration: InputDecoration(
                hintText: '搜索深夜食堂…',
                prefixIcon:
                    Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(100),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error.isNotEmpty
                    ? ErrorView(message: _error, onRetry: _load)
                    : _items.isEmpty
                        ? const EmptyView(message: '暂无内容')
                        : ListView.separated(
                            controller: _scroll,
                            padding: const EdgeInsets.all(14),
                            itemCount: _items.length + (_noMore ? 0 : 1),
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i >= _items.length) {
                                return const TailLoader();
                              }
                              final m = _items[i];
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    _titleOf(m),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    _subOf(m),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant),
                                  ),
                                  trailing: Icon(Icons.chevron_right_rounded,
                                      color: cs.onSurfaceVariant),
                                  onTap: () => _openDetail(_idOf(m)),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  /// 博客详情（对齐 qt GetBlogInfoReq2）。
  Future<void> _openDetail(String id) async {
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _BlogDetailPage(api: _api, blogId: id),
      ),
    );
  }
}

/// 博客详情页。
class _BlogDetailPage extends StatefulWidget {
  const _BlogDetailPage({required this.api, required this.blogId});

  final JmApi api;
  final String blogId;

  @override
  State<_BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends State<_BlogDetailPage> {
  dynamic _detail;
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
      final data = await widget.api.getBlogInfo(widget.blogId);
      if (!mounted) return;
      setState(() {
        _detail = data;
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = _detail is Map<String, dynamic>
        ? _detail as Map<String, dynamic>
        : <String, dynamic>{};
    final title =
        (m['title'] ?? m['name'] ?? '详情').toString();
    final rawContent = (m['content'] ??
            m['description'] ??
            m['blog_content'] ??
            '')
        .toString();
    // 服务端博客内容为 HTML，剥离标签后展示纯文本。
    final content = stripHtmlTags(rawContent);

    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1)),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text(title,
                        style: tt.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text(
                      content,
                      style: tt.bodyMedium?.copyWith(height: 1.7),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '— 深夜食堂 —',
                      textAlign: TextAlign.center,
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
    );
  }
}
