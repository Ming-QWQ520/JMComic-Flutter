import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';
import '../blogs/blogs_page.dart';
import '../download/download_page.dart';
import '../settings/settings_page.dart';
import '../sign/sign_page.dart';
import 'favorites_page.dart';
import 'login_page.dart';

/// 我的页面（对齐 qt NavigationWidget 用户区）：登录态、收藏、历史、
/// 下载管理、签到、深夜食堂、设置入口。
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
                    backgroundImage: user != null &&
                            !user.photo.startsWith('nopic-') &&
                            user.photo.isNotEmpty
                        ? NetworkImage(state.api.avatarUrl(user.photo))
                        : null,
                    child: user == null ||
                            user.photo.startsWith('nopic-') ||
                            user.photo.isEmpty
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
                                '${user.levelName.isEmpty ? 'Lv.${user.level}' : user.levelName}'
                                ' · J币 ${user.coin} · 经验 ${user.exp}',
                                style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '收藏 ${user.albumFavorites}/${user.albumFavoritesMax}',
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
                          // 对齐 qt Logout：清除本地登录态
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
            _tile(context, Icons.bookmark_rounded, '我的收藏', '收藏夹管理 / 收藏的漫画',
                const Color(0xFFE91E63),
                () => _pushLogged(context, const FavoritesPage())),
            _tile(context, Icons.history_rounded, '浏览历史', '最近看过的漫画',
                const Color(0xFF17A2B8),
                () => _pushLogged(context, const HistoryPage())),
            _tile(context, Icons.download_rounded, '下载管理', '下载队列 / 本地书架 / 离线阅读',
                const Color(0xFF4CAF50),
                () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const DownloadPage()))),
          ]),
          const SizedBox(height: 14),
          // ---------- 账号服务 ----------
          SectionHeader(title: '账号服务'),
          _group(context, <Widget>[
            _tile(context, Icons.emoji_events_rounded, '每日签到', '签到日历 / J币奖励',
                const Color(0xFFFFC107),
                () => _pushLogged(context, const SignPage())),
            _tile(context, Icons.my_library_books_rounded, '我的评论', '发布的评论记录',
                const Color(0xFF9B59B6),
                () => _pushLogged(context, const MyCommentsPage())),
          ]),
          const SizedBox(height: 14),
          // ---------- 更多 ----------
          SectionHeader(title: '更多'),
          _group(context, <Widget>[
            _tile(context, Icons.restaurant_rounded, '深夜食堂', '专栏文章 / 随笔',
                const Color(0xFFFF7B00),
                () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const BlogsPage()))),
            _tile(context, Icons.settings_rounded, '设置',
                '主题 / 线路 / DoH / 阅读设置',
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

/// 我的评论页（对齐 qt GetMyCommentReq2）。
class MyCommentsPage extends StatefulWidget {
  const MyCommentsPage({super.key});

  @override
  State<MyCommentsPage> createState() => _MyCommentsPageState();
}

class _MyCommentsPageState extends State<MyCommentsPage> {
  final JmApi _api = JmApi.instance;
  final List<CommentInfo> _items = <CommentInfo>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getMyComments(app.user!.id, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(data.list);
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的评论')),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(message: '还没有发布过评论')
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              c.linkBookName.isEmpty
                                  ? c.content
                                  : c.linkBookName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              c.linkBookName.isEmpty
                                  ? '赞 ${c.likes}'
                                  : c.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: c.linkBookId.isNotEmpty
                                ? Icon(Icons.chevron_right_rounded,
                                    color: cs.onSurfaceVariant)
                                : null,
                            onTap: c.linkBookId.isNotEmpty
                                ? () => Navigator.pushNamed(
                                    context, '/album',
                                    arguments: c.linkBookId)
                                : null,
                          ),
                        );
                      },
                    ),
    );
  }
}
