import 'package:flutter/material.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../widgets/album_card.dart';
import '../../widgets/feedback.dart';

/// 每周更新页：按星期筛选连载。
class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  final JmApi _api = JmApi.instance;
  List<dynamic> _days = <dynamic>[];
  bool _loading = true;
  String _error = '';
  int _selected = -1;
  List<SearchAlbum> _albums = <SearchAlbum>[];
  bool _albumsLoading = false;

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
      final data = await _api.getWeek();
      List days = const [];
      if (data is Map) {
        days = (data['list'] ?? data['weeks'] ?? data['data'] ?? []) as List;
      } else if (data is List) {
        days = data;
      }
      if (!mounted) return;
      setState(() {
        _days = days;
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
    if (i < 0 || i >= _days.length) return;
    final day = _days[i];
    String slug = '';
    if (day is Map) {
      slug = (day['slug'] ?? day['id'] ?? '').toString();
    }
    if (slug.isEmpty) {
      if (mounted) setState(() => _albumsLoading = false);
      return;
    }
    try {
      final data = await _api.getWeekFilter({'week': slug});
      if (!mounted) return;
      setState(() {
        _albums = SearchAlbum.listFrom(data);
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
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('每周更新')),
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
                          final day = _days[i];
                          final label = day is Map
                              ? (day['name'] ??
                                      day['title'] ??
                                      day['slug'] ??
                                      '')
                                  .toString()
                              : day.toString();
                          final sel = i == _selected;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            child: ChoiceChip(
                              label: Text(label),
                              labelStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: sel
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              selected: sel,
                              onSelected: (_) => _select(i),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                      child: SectionHeader(title: '本日更新'),
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
                    Text(
                      '数据来自 week / week-filter 接口',
                      style: tt.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
    );
  }
}
