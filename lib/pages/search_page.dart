import 'package:flutter/material.dart';

import '../api/jm_api.dart';
import '../api/models.dart';
import '../widgets/common.dart';

/// 搜索页：关键词搜索 + 排序 + 热门标签。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  AlbumGrid? _grid;
  String _keyword = '';
  String _order = 'mr';
  List<String> _hotTags = <String>[];

  static const Map<String, String> _orders = <String, String>{
    'mr': '最新',
    'mt': '最多浏览',
    'tf': '最多喜欢',
    't': '最新发布',
  };

  @override
  void initState() {
    super.initState();
    _loadHotTags();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
        _hotTags = tags.take(30).toList();
      });
    } catch (_) {
      // 热门标签失败不影响搜索
    }
  }

  void _search([String? kw]) {
    final k = (kw ?? _ctrl.text).trim();
    if (k.isEmpty) return;
    setState(() {
      _keyword = k;
      _grid = AlbumGrid(fetchPage: _fetch);
    });
  }

  Future<List<SearchAlbum>?> _fetch(int page) async {
    try {
      final r =
          await JmApi.instance.searchComic(_keyword, page, order: _order);
      return r.content;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索漫画 / 主题 / 作者:名字',
            border: InputBorder.none,
          ),
          onSubmitted: (String v) => _search(v),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _search(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            onSelected: (String v) {
              setState(() => _order = v);
              if (_keyword.isNotEmpty) _search(_keyword);
            },
            itemBuilder: (_) => _orders.entries
                .map((MapEntry<String, String> e) => PopupMenuItem<String>(
                      value: e.key,
                      child: Text(_order == e.key ? '${e.value} ✓' : e.value),
                    ))
                .toList(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_keyword.isEmpty && _hotTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _hotTags
                      .take(18)
                      .map((String t) => ActionChip(
                            label:
                                Text(t, style: const TextStyle(fontSize: 12)),
                            onPressed: () {
                              _ctrl.text = t;
                              _search(t);
                            },
                          ))
                      .toList(),
                ),
              ),
            ),
          Expanded(
            child: _grid == null
                ? const EmptyBox(message: '输入关键词开始搜索')
                : _grid!,
          ),
        ],
      ),
    );
  }
}
