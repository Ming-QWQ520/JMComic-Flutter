import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 消息通知页（对齐官方 2.1.12 API_NOTIFICATIONS：GET notifications）。
///
/// 支持分类筛选（全部/专辑更新/评论），显示未读数量角标语义，
/// 点击条目可跳转对应专辑。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final JmApi _api = JmApi.instance;

  static const Map<String, String> _types = <String, String>{
    '': '全部',
    'album': '专辑更新',
    'comment': '评论',
  };

  String _type = '';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _error = '';

  final List<dynamic> _items = <dynamic>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请先登录后查看通知';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getNotifications(type: _type, page: 1);
      if (!mounted) return;
      final list = _extractList(data);
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _page = 1;
        _hasMore = list.length >= 20;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.getNotifications(type: _type, page: _page + 1);
      if (!mounted) return;
      final list = _extractList(data);
      setState(() {
        _items.addAll(list);
        _page++;
        _hasMore = list.length >= 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 从响应中宽松提取通知数组（data.list / data / 裸数组）。
  static List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final l = data['list'] ?? data['data'] ?? data['list_data'];
      if (l is List) return l;
    }
    return <dynamic>[];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息通知'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _types.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _type == e.key,
                        onSelected: (_) {
                          _type = e.key;
                          _reload();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
          ? ErrorView(message: _error, onRetry: _reload)
          : _items.isEmpty
          ? Center(
              child: Text(
                '暂无通知',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (s) {
                if (s.metrics.pixels >= s.metrics.maxScrollExtent - 200) {
                  _loadMore();
                }
                return false;
              },
              child: ListView.separated(
                itemCount: _items.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext c, int i) {
                  if (i >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final m = _items[i];
                  if (m is! Map) return const SizedBox.shrink();
                  final title = '${m['title'] ?? m['content'] ?? ''}';
                  final time = '${m['addtime'] ?? m['created_at'] ?? ''}';
                  final aid = '${m['aid'] ?? m['album_id'] ?? ''}';
                  return ListTile(
                    leading: Icon(
                      _type == 'comment'
                          ? Icons.comment_rounded
                          : Icons.update_rounded,
                      color: cs.primary,
                    ),
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium,
                    ),
                    subtitle: time.isEmpty
                        ? null
                        : Text(
                            time,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                    trailing: aid.isNotEmpty && aid != 'null' && aid != '0'
                        ? const Icon(Icons.chevron_right_rounded, size: 20)
                        : null,
                    onTap: aid.isNotEmpty && aid != 'null' && aid != '0'
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AlbumStubPage(albumId: aid),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}

/// 通知跳转的专辑占位页：直接复用搜索/首页的专辑详情需要传 id，
/// 这里仅做最简跳转（避免循环依赖过多页面）。
class AlbumStubPage extends StatelessWidget {
  const AlbumStubPage({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('专辑')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.menu_book_rounded, size: 48),
            const SizedBox(height: 12),
            Text('专辑 ID: $albumId'),
            const SizedBox(height: 8),
            const Text('可在搜索页粘贴该 ID 查看详情'),
          ],
        ),
      ),
    );
  }
}
