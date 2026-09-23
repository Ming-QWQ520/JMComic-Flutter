import 'package:flutter/material.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../widgets/album_card.dart';
import '../../widgets/feedback.dart';

/// 每周更新页（对齐 qt WeekView）。
///
/// - GET week 拉取星期分类（categories: [{id, time}]）；
/// - GET week/filter?id=&type= 按 manga/hanman/another 三个类型页签加载。
class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage>
    with SingleTickerProviderStateMixin {
  final JmApi _api = JmApi.instance;
  late final TabController _typeCtrl =
      TabController(length: 3, vsync: this);

  /// 星期分类（id + time 标题）。
  final List<Map<String, String>> _days = <Map<String, String>>[];
  bool _loading = true;
  String _error = '';
  int _selected = 0;
  List<SearchAlbum> _albums = <SearchAlbum>[];
  bool _albumsLoading = false;

  /// 类型页签（对齐 qt typeIndexDict）。
  static const List<String> _types = <String>['manga', 'hanman', 'another'];
  static const List<String> _typeLabels = <String>['漫画', '韩漫', '其他'];

  @override
  void initState() {
    super.initState();
    _load();
    _typeCtrl.addListener(_onTypeChanged);
  }

  @override
  void dispose() {
    _typeCtrl.removeListener(_onTypeChanged);
    _typeCtrl.dispose();
    super.dispose();
  }

  void _onTypeChanged() {
    if (!_typeCtrl.indexIsChanging) _select(_selected);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getWeek();
      final days = <Map<String, String>>[];
      if (data is Map) {
        final cats = data['categories'];
        if (cats is List) {
          for (final v in cats) {
            if (v is Map) {
              days.add(<String, String>{
                'id': '${v['id'] ?? ''}',
                'time': '${v['time'] ?? v['title'] ?? v['name'] ?? ''}',
              });
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _days
          ..clear()
          ..addAll(days);
        _loading = false;
      });
      if (days.isNotEmpty) _select(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _select(int i) async {
    setState(() {
      _selected = i;
      _albumsLoading = true;
    });
    if (i < 0 || i >= _days.length) {
      if (mounted) setState(() => _albumsLoading = false);
      return;
    }
    final id = _days[i]['id'] ?? '';
    final type = _types[_typeCtrl.index];
    if (id.isEmpty) {
      if (mounted) setState(() => _albumsLoading = false);
      return;
    }
    try {
      final list = await _api.getWeekFilter(id, type);
      if (!mounted) return;
      setState(() {
        _albums = list;
        _albumsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _albums = <SearchAlbum>[];
        _albumsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每周更新'),
        bottom: TabBar(
          controller: _typeCtrl,
          tabs: _typeLabels
              .map((String l) => Tab(text: l))
              .toList(),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _days.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final label = _days[i]['time'] ?? '周${i + 1}';
                          final sel = i == _selected;
                          return ChoiceChip(
                            label: Text(label),
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w500,
                            ),
                            selected: sel,
                            onSelected: (_) => _select(i),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _albumsLoading
                          ? const LoadingView()
                          : _albums.isEmpty
                              ? const EmptyView(message: '当日暂无更新')
                              : GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 4, 16, 16),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 160,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 0.55,
                                  ),
                                  itemCount: _albums.length,
                                  itemBuilder: (_, i) => AlbumCard(
                                    album: _albums[i],
                                    onTap: () => Navigator.pushNamed(
                                        context, '/album',
                                        arguments: _albums[i]),
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}
