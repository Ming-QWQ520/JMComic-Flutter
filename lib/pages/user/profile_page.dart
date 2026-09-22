import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_card.dart';
import '../../widgets/feedback.dart';
import '../media/media_page.dart';
import '../settings/settings_page.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'favorites_page.dart';

/// 我的页面：登录态、收藏、历史、通知、任务、多媒体、设置入口。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ---------- 用户卡片 ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: cs.primary.withValues(alpha: 0.14),
                    backgroundImage: user == null ||
                            state.api.avatarUrl(user.photo).isEmpty
                        ? null
                        : NetworkImage(state.api.avatarUrl(user.photo)),
                    child: user == null
                        ? Icon(Icons.person_rounded,
                            color: cs.primary, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: user == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('未登录',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text('登录后可同步收藏与历史',
                                  style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant)),
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
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16)),
                                  ),
                                  if (user.isVip) ...<Widget>[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.tertiary.withValues(
                                            alpha: 0.16),
                                        borderRadius:
                                            BorderRadius.circular(100),
                                      ),
                                      child: Text('VIP',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: cs.tertiary)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Lv.${user.level} · J币 ${user.coin} · 经验 ${user.exp}',
                                style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant),
                              ),
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
                        await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => const LoginPage()));
                      }
                    },
                    child: Text(state.isLogged ? '退出' : '登录'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 阅读服务 ----------
          SectionHeader(title: '阅读服务'),
          _group(context, <Widget>[
            _tile(context, Icons.bookmark_rounded, '我的收藏', '收藏的漫画',
                const Color(0xFF6C5CE7),
                () => _pushLogged(context, const FavoritesPage())),
            _tile(context, Icons.history_rounded, '浏览历史', '最近看过的漫画',
                const Color(0xFF00B894),
                () => _pushLogged(context, const HistoryPage())),
            _tile(context, Icons.track_changes_rounded, '追更列表', '订阅的连载更新',
                const Color(0xFFE67E22),
                () => _pushLogged(context, const TrackListPage())),
          ]),
          const SizedBox(height: 14),
          // ---------- 账号服务 ----------
          SectionHeader(title: '账号服务'),
          _group(context, <Widget>[
            _tile(context, Icons.notifications_rounded, '通知中心', '系统与互动消息',
                const Color(0xFFE74C3C),
                () => _pushLogged(context, const NotificationsPage())),
            _tile(context, Icons.emoji_events_rounded, '任务与签到',
                '每日签到 / 任务 / J币', const Color(0xFFF1C40F),
                () => _pushLogged(context, const TasksPage())),
          ]),
          const SizedBox(height: 14),
          // ---------- 更多 ----------
          SectionHeader(title: '更多'),
          _group(context, <Widget>[
            _tile(context, Icons.auto_stories_rounded, '多媒体中心',
                '小说 / 游戏 / 视频 / 博客', const Color(0xFF9B59B6),
                () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const MediaPage()))),
            _tile(context, Icons.settings_rounded, '设置', '主题 / 翻页 / 线路 / 语言',
                const Color(0xFF64748B),
                () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const SettingsPage()))),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'JMComic-Flutter · 仅用于学习研究',
              style: tt.labelSmall?.copyWith(color: cs.outline),
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

  Widget _group(BuildContext context, List<Widget> children) {
    return Card(
      child: Column(children: children),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub,
      Color color, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing:
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
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
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(message: '暂无追更的连载')
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.55,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        return AlbumCard(
                          album: a,
                          onTap: () => Navigator.pushNamed(
                              context, '/album', arguments: a),
                        );
                      },
                    ),
    );
  }
}
