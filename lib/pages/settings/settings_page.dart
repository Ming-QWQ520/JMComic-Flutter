import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_client.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 设置页：主题模式 / 阅读设置 / 图源 / 语言 / 线路。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionHeader(title: '外观'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: state.themeMode,
              onChanged: (ThemeMode? v) {
                if (v != null) state.setThemeMode(v);
              },
              child: Column(
                children: const <Widget>[
                  RadioListTile<ThemeMode>(
                    title: Text('跟随系统'),
                    subtitle: Text('默认 · 自动切换深浅色'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('浅色模式'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('深色模式'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(title: '阅读'),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  title: const Text('音量键翻页',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('阅读时音量+/- 翻上一页/下一页'),
                  value: state.volumeKeyPaging,
                  onChanged: (bool v) => state.setVolumeKeyPaging(v),
                ),
                SwitchListTile(
                  title: const Text('阅读时屏幕常亮',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('进入阅读器保持屏幕常亮'),
                  value: state.keepScreenOn,
                  onChanged: (bool v) => state.setKeepScreenOn(v),
                ),
                SwitchListTile(
                  title: const Text('加速图源',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('comic_read 使用 express=on'),
                  value: state.express,
                  onChanged: (bool v) => state.setExpress(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(title: '翻页方向'),
          SegmentedButton<ReadDirection>(
            style: ButtonStyle(
              visualDensity: VisualDensity.comfortable,
            ),
            segments: const <ButtonSegment<ReadDirection>>[
              ButtonSegment<ReadDirection>(
                value: ReadDirection.vertical,
                icon: Icon(Icons.swap_vert_rounded),
                label: Text('上下翻页'),
              ),
              ButtonSegment<ReadDirection>(
                value: ReadDirection.horizontal,
                icon: Icon(Icons.swap_horiz_rounded),
                label: Text('左右翻页'),
              ),
            ],
            selected: <ReadDirection>{state.readDirection},
            onSelectionChanged: (Set<ReadDirection> s) =>
                state.setReadDirection(s.first),
          ),
          const SizedBox(height: 16),
          SectionHeader(title: '语言'),
          Card(
            child: RadioGroup<String>(
              groupValue: state.lang,
              onChanged: (String? v) {
                if (v != null) state.setLang(v);
              },
              child: Column(
                children: const <Widget>[
                  RadioListTile<String>(
                    title: Text('繁體中文 (TW)'),
                    value: 'TW',
                  ),
                  RadioListTile<String>(
                    title: Text('简体中文 (CN)'),
                    value: 'CN',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(title: '线路'),
          const LinesCard(),
          const SizedBox(height: 16),
          SectionHeader(title: '关于'),
          Card(
            child: ListTile(
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.info_outline_rounded, color: cs.primary),
              ),
              title: const Text('JMComic-Flutter',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'v1.0.0 · Flutter 3.47.5\n'
                '基于 JMcomic-API 协议逆向实现，覆盖全部 70 个端点。\n'
                '仅供学习研究，请勿用于商业用途。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 线路切换卡片。
class LinesCard extends StatefulWidget {
  const LinesCard({super.key});

  @override
  State<LinesCard> createState() => _LinesCardState();
}

class _LinesCardState extends State<LinesCard> {
  int _current = -1;
  List<List<String>> _lines = <List<String>>[];

  @override
  void initState() {
    super.initState();
    final c = JmClient.instance;
    _lines = c.lines;
    final host = c.baseUrl
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('/', '');
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].first.contains(host)) _current = i;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: <Widget>[
          if (_lines.isEmpty)
            const ListTile(
              leading: Icon(Icons.lan_outlined),
              title: Text('当前: 自动线路'),
              subtitle: Text('未获取到线路列表（启动时自动解析）'),
            )
          else
            RadioGroup<int>(
              groupValue: _current,
              onChanged: (int? v) {
                if (v == null) return;
                JmClient.instance.switchLine(v);
                setState(() => _current = v);
                final line = _lines[v];
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('已切换线路: '
                        '${line.length > 1 ? line[1] : line[0]}')));
              },
              child: Column(
                children: List<Widget>.generate(_lines.length, (int i) {
                  final line = _lines[i];
                  return RadioListTile<int>(
                    title: Text(line.length > 1 ? line[1] : line[0]),
                    subtitle:
                        Text(line[0], style: const TextStyle(fontSize: 11)),
                    value: i,
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
