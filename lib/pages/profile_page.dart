import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'favorites_page.dart';
import 'login_page.dart';
import 'media_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import '../api/jm_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// 我的页面：登录态、收藏、历史、通知、任务、多媒体、设置入口。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          _header(context, state, user),
          const SizedBox(height: 12),
          _card(context, <Widget>[
            _tile(
              context,
              Icons.bookmark_rounded,
              '我的收藏',
              '收藏的漫画',
              () => _pushLogged(
                  context, const FavoritesPage(kind: FavoriteKind.album)),
            ),
            _tile(
              context,
              Icons.history_rounded,
              '浏览历史',
              '看过的漫画',
              () => _pushLogged(context, const HistoryPage()),
            ),
            _tile(
              context,
              Icons.track_changes_rounded,
              '追更列表',
              '订阅的连载',
              () => _pushLogged(context, const TrackListPage()),
            ),
            _tile(
              context,
              Icons.notifications_rounded,
              '通知中心',
              '系统与互动消息',
              () => _pushLogged(context, const NotificationsPage()),
            ),
            _tile(
              context,
              Icons.emoji_events_rounded,
              '任务与签到',
              '每日签到 / 任务 / J币',
              () => _pushLogged(context, const TasksPage()),
            ),
          ]),
          const SizedBox(height: 12),
          _card(context, <Widget>[
            _tile(
              context,
              Icons.auto_stories_rounded,
              '多媒体中心',
              '小说 / 游戏 / 视频 / 博客',
              () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const MediaPage())),
            ),
            _tile(
              context,
              Icons.settings_rounded,
              '设置',
              '主题 / 翻页 / 线路 / 语言',
              () => Navigator.push(context,
                  MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
            ),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'JMComic-Flutter · 仅用于学习研究',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _pushLogged(BuildContext context, Widget page) async {
    final state = context.read<AppState>();
    if (!state.isLogged) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录')));
      await Navigator.push(
          context, MaterialPageRoute<void>(builder: (_) => const LoginPage()));
      return;
    }
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _header(BuildContext context, AppState state, LoginData? user) {
    final cs = Theme.of(context).colorScheme;
    final avatar = user == null ? '' : state.api.avatarUrl(user.photo);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primaryContainer,
              backgroundImage:
                  avatar.isEmpty ? null : NetworkImage(avatar) as ImageProvider,
              child: avatar.isEmpty
                  ? Icon(Icons.person_rounded, color: cs.onPrimaryContainer)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: user == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('未登录'),
                        Text('登录后可同步收藏与历史',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(user.username,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            if (user.isVip) ...<Widget>[
                              const SizedBox(width: 6),
                              Chip(
                                label: const Text('VIP',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: cs.tertiaryContainer,
                              ),
                            ],
                          ],
                        ),
                        Text(
                            '等级 ${user.level} · J币 ${user.coin} · 经验 ${user.exp}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
            ),
            FilledButton.tonal(
              onPressed: () async {
                if (state.isLogged) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext c) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('确定退出当前账号吗？'),
                      actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('退出')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await state.api.logout();
                    } catch (_) {}
                    await state.clearUser();
                  }
                } else {
                  await Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => const LoginPage()));
                }
              },
              child: Text(state.isLogged ? '退出' : '登录'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Card(
      child: Column(children: children),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// 追更列表页。
class TrackListPage extends StatefulWidget {
  const TrackListPage({super.key});

  @override
  State<TrackListPage> createState() => _TrackListPageState();
}

class _TrackListPageState extends State<TrackListPage> {
  List<SearchAlbum> _items = <SearchAlbum>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await JmApi.instance.getTrackList(1);
      if (!mounted) return;
      setState(() {
        _items = list;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('追更列表')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? ErrorBox(message: _error, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyBox(message: '暂无追更的连载')
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.52,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (BuildContext c, int i) => AlbumCard(
                        album: _items[i],
                        onTap: () => Navigator.pushNamed(context, '/album',
                            arguments: _items[i]),
                      ),
                    ),
    );
  }
}
