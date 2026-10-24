import 'package:flutter/material.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../services/image_store.dart';
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
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _subOf(m).isEmpty
                                          ? '点击查看全文'
                                          : _subOf(m),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ),
                                  trailing: Icon(Icons.chevron_right_rounded,
                                      color: cs.onSurfaceVariant),
                                  onTap: () =>
                                      _openDetail(_idOf(m), m),
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
  ///
  /// 修复：详情接口存在、列表也正常，但点击进入后看不到正文 ——
  /// 服务端 /blog 响应 data 形如 `{"info": {...}}`，正文嵌套在 info
  /// 字段下，旧实现直接从顶层读 title/content 永远为空。现把整个
  /// 列表项一并传给详情页作兑底数据源（列表项本身已含完整 content）。
  Future<void> _openDetail(String id, Map<String, dynamic> fallback) async {
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            _BlogDetailPage(api: _api, blogId: id, fallback: fallback),
      ),
    );
  }
}

/// 博客详情页。
///
/// 关键修复（「深夜食堂可显示标题但点击进入无法查看内容」）：
/// 服务端 /blog?id= 响应 data 为 `{"info": {...}}`，标题/正文嵌套在
/// info 字段下；旧实现从顶层读取 title/content 永远为空，页面只有
/// 一个「详情」标题。现按优先级解包：data.info > data 本身 >
/// 列表页传入的条目兑底（列表项自身已含完整 content）。
/// 正文为富文本 HTML（含配图 <img>），按 文本段 + 图片段 拆分渲染，
/// 图片统一走 ImageStore（带反爬 UA 与换线路重试），不再只显示纯文字。
class _BlogDetailPage extends StatefulWidget {
  const _BlogDetailPage({
    required this.api,
    required this.blogId,
    this.fallback = const <String, dynamic>{},
  });

  final JmApi api;
  final String blogId;

  /// 列表页条目（含完整 content），详情接口失败/缺字段时兑底。
  final Map<String, dynamic> fallback;

  @override
  State<_BlogDetailPage> createState() => _BlogDetailPageState();
}

class _BlogDetailPageState extends State<_BlogDetailPage> {
  Map<String, dynamic> _detail = <String, dynamic>{};
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
        _detail = _unwrap(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 详情接口失败不白屏：列表项里已有完整 content，直接兑底展示。
      if (widget.fallback.isNotEmpty &&
          _extractContent(widget.fallback).trim().isNotEmpty) {
        setState(() {
          _detail = widget.fallback;
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 解包响应：`{"info": {...}}` → info；否则原样返回 Map。
  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final info = data['info'];
      if (info is Map<String, dynamic> &&
          (info['content'] != null || info['title'] != null)) {
        return info;
      }
      return data;
    }
    return widget.fallback;
  }

  static String _extractContent(Map<String, dynamic> m) =>
      (m['content'] ?? m['description'] ?? m['blog_content'] ?? '').toString();

  /// 把服务端 HTML 正文拆成 (文本 | 图片URL) 有序段落。
  List<_BlogBlock> _parseBlocks(String html) {
    final blocks = <_BlogBlock>[];
    if (html.trim().isEmpty) return blocks;
    final imgRe = RegExp(
      "<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']",
      caseSensitive: false,
    );
    var last = 0;
    for (final m in imgRe.allMatches(html)) {
      final text = html.substring(last, m.start);
      if (text.trim().isNotEmpty) {
        blocks.add(_BlogBlock.text(stripHtmlTags(text)));
      }
      final src = m.group(1)?.trim() ?? '';
      if (src.isNotEmpty) blocks.add(_BlogBlock.image(src));
      last = m.end;
    }
    final tail = html.substring(last);
    if (tail.trim().isNotEmpty) {
      blocks.add(_BlogBlock.text(stripHtmlTags(tail)));
    }
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = _detail;
    final title = (m['title'] ?? m['name'] ?? '深夜食堂').toString();
    final rawContent = _extractContent(m);
    final blocks = _parseBlocks(rawContent);
    final date = (m['date'] ?? m['addtime'] ?? '').toString();
    final author = (m['username'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1)),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : blocks.isEmpty
                  ? const EmptyView(message: '正文内容为空')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: blocks.length + 2,
                      itemBuilder: (_, i) {
                        // 头部：标题 + 作者/日期
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(title,
                                    style: tt.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.3)),
                                const SizedBox(height: 6),
                                if (author.isNotEmpty || date.isNotEmpty)
                                  Text(
                                    <String>[
                                      if (author.isNotEmpty) '作者：$author',
                                      if (date.isNotEmpty) date,
                                    ].join(' · '),
                                    style: tt.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant),
                                  ),
                                const Divider(height: 20),
                              ],
                            ),
                          );
                        }
                        // 尾部落款
                        if (i == blocks.length + 1) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text(
                              '— 深夜食堂 —',
                              textAlign: TextAlign.center,
                              style: tt.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          );
                        }
                        final b = blocks[i - 1];
                        if (b.isImage) {
                          final url = b.imageUrl;
                          // 相对路径补图片域名；绝对 URL 直接使用
                          // （ImageStore 内部会按当前线路替换 host）。
                          final resolved = url.startsWith('http')
                              ? url
                              : JmApi.instance.coverUrl('').isNotEmpty
                                  ? '${_imgHost()}/$url'
                                  : url;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: GestureDetector(
                                onTap: resolved.isEmpty
                                    ? null
                                    : () => _showImage(context, resolved),
                                child: StoreImage(
                                  url: resolved,
                                  fit: BoxFit.fitWidth,
                                  placeholder: (BuildContext c) => Container(
                                    height: 180,
                                    color: cs.surfaceContainerHighest,
                                    child: const Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  ),
                                  error: (BuildContext c) => Container(
                                    height: 120,
                                    color: cs.surfaceContainerHighest,
                                    alignment: Alignment.center,
                                    child: Icon(Icons.broken_image_outlined,
                                        color: cs.outline),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            b.text,
                            style: tt.bodyMedium?.copyWith(height: 1.7),
                          ),
                        );
                      },
                    ),
    );
  }

  String _imgHost() {
    final host = JmApi.instance.coverUrl('0');
    // coverUrl 返回 {img}/media/albums/0_3x4.jpg；截取到域名即可
    final idx = host.indexOf('/media/');
    return idx > 0 ? host.substring(0, idx) : '';
  }

  void _showImage(BuildContext context, String url) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, _, _) => _BlogImageViewer(url: url),
        transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

class _BlogBlock {
  const _BlogBlock.text(this.text)
      : isImage = false,
        imageUrl = '';

  const _BlogBlock.image(this.imageUrl)
      : isImage = true,
        text = '';

  final bool isImage;
  final String text;
  final String imageUrl;
}

/// 博客配图全屏查看器（点击图片放大，点击背景关闭）。
class _BlogImageViewer extends StatelessWidget {
  const _BlogImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: InteractiveViewer(
          maxScale: 4,
          child: StoreImage(url: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
