import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/jm_api.dart';

/// 多媒体中心：小说 / 游戏 / 视频 / 博客（覆盖全部媒体域 API）。
class MediaPage extends StatelessWidget {
  const MediaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('多媒体中心'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '小说'),
              Tab(text: '游戏'),
              Tab(text: '视频'),
              Tab(text: '博客'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            MediaListView(kind: MediaKind.novel),
            MediaListView(kind: MediaKind.game),
            MediaListView(kind: MediaKind.video),
            MediaListView(kind: MediaKind.blog),
          ],
        ),
      ),
    );
  }
}

enum MediaKind { novel, game, video, blog }

/// 媒体列表视图（JSON 驱动，兼容不同响应结构）。
class MediaListView extends StatefulWidget {
  const MediaListView({super.key, required this.kind});

  final MediaKind kind;

  @override
  State<MediaListView> createState() => _MediaListViewState();
}

class _MediaListViewState extends State<MediaListView>
    with AutomaticKeepAliveClientMixin {
  final JmApi _api = JmApi.instance;
  final ScrollController _scroll = ScrollController();

  List<dynamic> _items = <dynamic>[];
  int _page = 1;
  bool _loading = false;
  bool _failed = false;
  bool _noMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<dynamic> _fetch(int page) {
    switch (widget.kind) {
      case MediaKind.novel:
        return _api.getNovelList(page: page);
      case MediaKind.game:
        return _api.getGamesList(page: page);
      case MediaKind.video:
        return _api.getVideosList(page: page);
      case MediaKind.blog:
        return _api.getBlogsList(page: page);
    }
  }

  List<dynamic> _extract(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      const keys = <String>[
        'list', 'content', 'novels', 'games', 'videos', 'blogs', 'items',
      ];
      for (final k in keys) {
        if (data[k] is List) return data[k] as List;
      }
    }
    return const <dynamic>[];
  }

  Future<void> _loadMore() async {
    if (_loading || _noMore || _failed) return;
    _loading = true;
    if (mounted) setState(() {});
    try {
      final data = await _fetch(_page);
      final list = _extract(data);
      if (!mounted) return;
      setState(() {
        if (list.isEmpty) {
          _noMore = true;
        } else {
          _items.addAll(list);
          _page++;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _failed = false);
    _loadMore();
  }

  String _titleOf(Map<dynamic, dynamic> m) {
    for (final k in const <String>['name', 'title', 'game_name']) {
      if (m[k] != null && m[k].toString().isNotEmpty) return m[k].toString();
    }
    return '(无标题)';
  }

  String _idOf(Map<dynamic, dynamic> m) {
    for (final k in const <String>['id', 'aid', 'game_id']) {
      if (m[k] != null && m[k].toString().isNotEmpty) return m[k].toString();
    }
    return '';
  }

  String _subOf(Map<dynamic, dynamic> m) {
    for (final k in const <String>[
      'author', 'category', 'description', 'category_title', 'uid',
    ]) {
      if (m[k] != null && m[k].toString().isNotEmpty) {
        final s = m[k].toString();
        return s.length > 60 ? s.substring(0, 60) : s;
      }
    }
    return '';
  }

  Future<void> _openDetail(Map<dynamic, dynamic> m) async {
    final id = _idOf(m);
    if (id.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该条目缺少 ID')));
      return;
    }
    try {
      dynamic detail;
      switch (widget.kind) {
        case MediaKind.novel:
          detail = await _api.getNovelDetail(id);
          break;
        case MediaKind.game:
          detail = await _api.getGameInfo(id);
          break;
        case MediaKind.video:
          detail = await _api.getVideoInfo(<String, dynamic>{'id': id});
          break;
        case MediaKind.blog:
          detail = await _api.getBlogInfo(id);
          break;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => JsonViewerPage(
            title: _titleOf(m),
            data: detail,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('加载失败'),
            FilledButton.tonal(onPressed: _retry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty && _noMore) {
      return const Center(child: Text('暂无内容'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _items = <dynamic>[];
          _page = 1;
          _noMore = false;
          _failed = false;
        });
        _loadMore();
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: _items.length + (_noMore ? 0 : 1),
        itemBuilder: (BuildContext c, int i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _items[i];
          if (item is! Map) {
            return ListTile(title: Text(item.toString()));
          }
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                switch (widget.kind) {
                  MediaKind.novel => '书',
                  MediaKind.game => '游',
                  MediaKind.video => '视',
                  MediaKind.blog => '博',
                },
              ),
            ),
            title: Text(_titleOf(item),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: _subOf(item).isEmpty
                ? null
                : Text(_subOf(item),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openDetail(item),
          );
        },
      ),
    );
  }
}

/// 通用 JSON 查看页（媒体详情 / 原始接口结果展示）。
class JsonViewerPage extends StatelessWidget {
  const JsonViewerPage({super.key, required this.title, this.data});

  final String title;
  final dynamic data;

  String get _pretty {
    try {
      const enc = JsonEncoder.withIndent('  ');
      return enc.convert(data);
    } catch (_) {
      return data?.toString() ?? '空';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _pretty,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
