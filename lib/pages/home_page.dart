import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/jm_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 首页：最新漫画无限流 + 每周更新/随机推荐入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.initError != null) {
      return Scaffold(
        body: ErrorBox(
          message: '主机解析失败：${state.initError}',
          onRetry: () => state.init(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('JMComic-Flutter'),
        actions: <Widget>[
          IconButton(
            tooltip: '每周更新',
            icon: const Icon(Icons.date_range_rounded),
            onPressed: () => Navigator.pushNamed(context, '/week'),
          ),
          IconButton(
            tooltip: '随机推荐',
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () => _openRandom(context),
          ),
        ],
      ),
      body: AlbumGrid(
        fetchPage: (int page) async {
          try {
            return await JmApi.instance.getLatest(page);
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }

  Future<void> _openRandom(BuildContext context) async {
    try {
      final data = await JmApi.instance.getRandomRecommend();
      final list = SearchAlbum.listFrom(data);
      if (!context.mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('随机推荐为空')),
        );
        return;
      }
      Navigator.pushNamed(context, '/album', arguments: list.first);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('随机推荐加载失败')),
      );
    }
  }
}

/// 每周更新页。
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
      List days = const <dynamic>[];
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
    setState(() => _selected = i);
    if (i < 0 || i >= _days.length) return;
    final day = _days[i];
    String slug = '';
    if (day is Map) {
      slug = (day['slug'] ?? day['id'] ?? '').toString();
    }
    if (slug.isEmpty) return;
    try {
      final data = await _api.getWeekFilter(<String, dynamic>{'week': slug});
      if (!mounted) return;
      setState(() => _albums = SearchAlbum.listFrom(data));
    } catch (_) {
      if (!mounted) return;
      setState(() => _albums = <SearchAlbum>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每周更新')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? ErrorBox(message: _error, onRetry: _load)
              : Column(
                  children: <Widget>[
                    SizedBox(
                      height: 56,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _days.length,
                        itemBuilder: (BuildContext c, int i) {
                          final day = _days[i];
                          final label = day is Map
                              ? (day['name'] ?? day['title'] ?? day['slug'] ?? '')
                                  .toString()
                              : day.toString();
                          final sel = i == _selected;
                          return Padding(
                            padding: const EdgeInsets.all(6),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: sel,
                              onSelected: (_) => _select(i),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _albums.isEmpty
                          ? const EmptyBox(message: '当日暂无更新')
                          : GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.52,
                              ),
                              itemCount: _albums.length,
                              itemBuilder: (BuildContext c, int i) => AlbumCard(
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
