import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 关于项目页（「更多 → 关于项目」/ 设置 → 关于）。
///
/// 展示：项目名称与介绍、作者信息、相关链接（B站 / GitHub / 抖音）、
/// 仓库 Star 数（GitHub API，进程冷启动时请求一次，切后台回前台不重复请求）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _repoUrl = 'https://github.com/Ming-QWQ520/JMComic-Flutter';

  static const List<(String, IconData, Color, String)> _links = <(
    String,
    IconData,
    Color,
    String
  )>[
    ('Bilibili 主页', Icons.smart_display_outlined, Color(0xFFFB7299),
        'https://space.bilibili.com/3546837476706334'),
    ('GitHub 仓库', Icons.code_rounded, Color(0xFF8B949E),
        'https://github.com/Ming-QWQ520'),
    ('抖音主页', Icons.music_note_rounded, Color(0xFF161823),
        'https://v.douyin.com/5HBLpptAMVI/'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('关于项目')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ---------- 项目卡 ----------
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  cs.primary.withValues(alpha: 0.18),
                  cs.primary.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'JM',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'JMComic-Flutter',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'v2.2.0 · API 协议对齐 tonquer/JMComic-qt',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '基于 JMcomic-API 的跨平台漫画阅读客户端（Android / Windows），'
                  '支持在线阅读、下载离线、收藏与评论。本项目仅供学习研究，'
                  '请于下载后 24 小时内删除，请支持正版。',
                  style: tt.bodySmall?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 12),
                // 作者
                Row(
                  children: <Widget>[
                    Icon(Icons.person_outline_rounded,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '作者：Ming (Ming-QWQ520)',
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ---------- Star 数 ----------
          SectionHeader(title: '项目数据'),
          Card(
            child: ListTile(
              leading: Icon(Icons.star_rounded,
                  size: 24, color: const Color(0xFFF5B301)),
              title: const Text('GitHub Stars'),
              subtitle: const Text('每次进入 APP 时请求一次（切后台返回不刷新）'),
              trailing: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  state.repoStars?.toString() ?? '…',
                  key: ValueKey<int?>(state.repoStars),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              onTap: () => StorageService.openUrl(_repoUrl),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 相关链接 ----------
          SectionHeader(title: '相关链接'),
          Card(
            child: Column(
              children: <Widget>[
                for (var i = 0; i < _links.length; i++) ...<Widget>[
                  _LinkTile(
                    label: _links[i].$1,
                    icon: _links[i].$2,
                    color: _links[i].$3,
                    url: _links[i].$4,
                  ),
                  if (i != _links.length - 1)
                    Divider(
                      height: 0.6,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '仅供学习研究 · 请于下载后 24 小时内删除',
              style: tt.labelSmall?.copyWith(color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// 外链条目。
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.url,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.open_in_new_rounded,
          size: 18, color: cs.onSurfaceVariant),
      onTap: () async {
        final ok = await StorageService.openUrl(url);
        if (!context.mounted || ok) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到可打开链接的应用')));
      },
    );
  }
}
