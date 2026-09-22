import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/jm_api.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 收藏 / 历史列表页。
enum FavoriteKind { album, history }

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, this.kind = FavoriteKind.album});

  final FavoriteKind kind;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _order = 'mr';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isHistory = widget.kind == FavoriteKind.history;
    return Scaffold(
      appBar: AppBar(
        title: Text(isHistory ? '浏览历史' : '我的收藏'),
        actions: isHistory
            ? null
            : <Widget>[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort_rounded),
                  onSelected: (String v) => setState(() => _order = v),
                  itemBuilder: (_) => const <PopupMenuItem<String>>[
                    PopupMenuItem<String>(value: 'mr', child: Text('最新收藏')),
                    PopupMenuItem<String>(value: 'tf', child: Text('最多喜欢')),
                    PopupMenuItem<String>(value: 'mt', child: Text('最多浏览')),
                  ],
                ),
              ],
      ),
      body: AlbumGrid(
        key: ValueKey<String>('fav-${widget.kind}-$_order-${state.isLogged}'),
        fetchPage: (int page) async {
          try {
            if (isHistory) {
              return await JmApi.instance.getWatchList(page);
            }
            return await JmApi.instance.getFavoriteList(
                page: page, order: _order);
          } catch (_) {
            return null;
          }
        },
      ),
    );
  }
}

/// 浏览历史页（复用收藏网格）。
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FavoritesPage(kind: FavoriteKind.history);
  }
}
