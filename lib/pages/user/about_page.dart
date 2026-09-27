import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/github_service.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 关于项目页。
///
/// 展示：项目名称与版本、简介（GitHub API description，不再硬编码）、
/// 作者信息、相关链接（B站 / GitHub / 抖音）、Star 数、检测更新
/// （最新版本 + 更新内容 + 立即更新，APK 下载走 gh-proxy.com 加速）、
/// 致谢列表。
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

  /// 致谢：项目/服务名 + 说明 + 链接。
  static const List<(String, String, String)> _thanks = <(String, String, String)>[
    (
      'tonquer/JMComic-qt',
      'API 协议与功能设计参考',
      'https://github.com/tonquer/JMComic-qt',
    ),
    (
      'jmcomic (Python)',
      'JM API 协议的开源实现参考',
      'https://github.com/hect0x7/JMComic-Core',
    ),
    (
      'gh-proxy.com',
      'GitHub 资源下载加速',
      'https://gh-proxy.com',
    ),
    (
      'Flutter',
      '跨平台 UI 框架',
      'https://flutter.dev',
    ),
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
                    // APP 图标（与启动器图标同源，体现项目品牌识别）。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Container(
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
                            'v$kAppVersion',
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
                // 简介：来自 GitHub API 的仓库 description（冷启动时随
                // Star 数一起拉取），不再硬编码。
                Text(
                  state.repoDescription ?? '仓库简介加载中…（可下拉重进刷新）',
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
          // ---------- 检测更新 ----------
          const _UpdateSection(),
          const SizedBox(height: 14),
          // ---------- Star 数 / 开源协议 ----------
          SectionHeader(title: '项目数据'),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.star_rounded,
                      size: 24, color: const Color(0xFFF5B301)),
                  title: const Text('GitHub Stars'),
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
                Divider(
                  height: 0.6,
                  indent: 16,
                  endIndent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.gavel_rounded,
                      size: 22, color: cs.primary),
                  title: const Text('开源协议'),
                  subtitle: Text(
                    state.repoLicense ?? '未声明（仅供学习研究）',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => StorageService.openUrl(
                    '$_repoUrl/blob/main/LICENSE',
                  ),
                ),
              ],
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
          const SizedBox(height: 14),
          // ---------- 致谢 ----------
          SectionHeader(title: '致谢'),
          Card(
            child: Column(
              children: <Widget>[
                for (var i = 0; i < _thanks.length; i++) ...<Widget>[
                  _LinkTile(
                    label: _thanks[i].$1,
                    subtitle: _thanks[i].$2,
                    icon: Icons.favorite_rounded,
                    color: cs.primary,
                    url: _thanks[i].$3,
                  ),
                  if (i != _thanks.length - 1)
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

/// 检测更新区块：检测最新 Release → 有更新时展示版本名与更新内容 →
/// 立即更新（Android 内下载 APK 并拉起安装器；桌面端跳转 Release 页）。
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  bool _checking = false;
  bool _checked = false;
  ReleaseInfo? _latest;
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  /// 设备主 ABI（冷启动后异步获取），用于挑选最优更新 APK。
  String _abi = '';

  @override
  void initState() {
    super.initState();
    StorageService.getDeviceAbi().then((String abi) {
      if (mounted) setState(() => _abi = abi);
    });
  }

  bool get _hasUpdate {
    final r = _latest;
    if (r == null || r.version.isEmpty) return false;
    return GithubService.isNewerVersion(r.version, kAppVersion);
  }

  /// 按设备 ABI 挑选最优 APK：
  /// - arm64-v8a 设备 → arm64 专用包，缺失回退 universal；
  /// - armeabi-v7a 设备 → 32 位包（arm64 包不兼容），缺失回退 universal；
  /// - x86_64 设备 → x86_64 包，缺失回退 universal；
  /// - 其他/未知 → universal。
  String _pickApk(ReleaseInfo r) {
    final urls = r.abiUrls;
    switch (_abi) {
      case 'arm64-v8a':
        return urls['arm64-v8a'] ?? urls['universal'] ?? r.apkUrl;
      case 'armeabi-v7a':
        return urls['armeabi-v7a'] ?? urls['universal'] ?? r.apkUrl;
      case 'x86_64':
        return urls['x86_64'] ?? urls['universal'] ?? r.apkUrl;
      default:
        return urls['universal'] ?? r.apkUrl;
    }
  }

  String _pickedArch(ReleaseInfo r) {
    final url = _pickApk(r);
    for (final arch in const <String>[
      'universal',
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ]) {
      if (url.contains(arch)) return arch;
    }
    return 'apk';
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = '';
    });
    final r = await GithubService.fetchLatestRelease();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = true;
      _latest = r;
    });
  }

  Future<void> _download() async {
    final r = _latest;
    if (r == null || _downloading) return;
    // 桌面端：直接打开 Release 页由用户手动下载。
    if (!Platform.isAndroid) {
      await StorageService.openUrl(r.htmlUrl);
      return;
    }
    final url = _pickApk(r);
    final arch = _pickedArch(r);
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = '准备下载（$arch）…';
    });
    try {
      final base = await getExternalStorageDirectory();
      final updateDir = Directory('${base!.path}/update');
      await updateDir.create(recursive: true);
      final savePath = '$updateDir/JMComic-Flutter-v${r.version}-$arch.apk';
      final file = await GithubService.downloadUpdate(
        url: url,
        savePath: savePath,
        onProgress: (double p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _downloading = false;
          _status = '下载失败，请检查网络后重试';
        });
        return;
      }
      setState(() => _status = '下载完成，正在拉起安装…');
      final ok = await StorageService.installApk(file.path);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = ok
            ? '已拉起系统安装器，请确认安装'
            : '无法拉起安装器，请允许"安装未知应用"后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = '下载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: '检测更新'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.system_update_alt_rounded,
                        size: 22, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '当前版本 v$kAppVersion',
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : FilledButton.tonal(
                            onPressed: _check,
                            child: const Text('检测更新'),
                          ),
                  ],
                ),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _status,
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                // 检测失败
                if (_checked && _latest == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '检测失败：无法连接 GitHub，请稍后重试',
                      style: tt.labelSmall?.copyWith(color: cs.error),
                    ),
                  ),
                // 已是最新
                if (_latest != null && !_hasUpdate)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '已是最新版本（服务端 v${_latest!.version}）',
                      style: tt.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                // 有更新：最新版本名 + 更新内容 + 立即更新
                if (_latest != null && _hasUpdate) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '发现新版本 v${_latest!.version}',
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                        if (_latest!.body.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: SingleChildScrollView(
                              child: Text(
                                _latest!.body.trim(),
                                style: tt.bodySmall?.copyWith(
                                  height: 1.5,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _downloading ? null : _download,
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        Platform.isAndroid ? '立即更新' : '前往 Release 页下载',
                      ),
                    ),
                  ),
                  if (_downloading) ...<Widget>[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _progress > 0
                          ? '${(_progress * 100).toStringAsFixed(1)}%'
                          : '连接中…',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
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
    this.subtitle,
  });

  final String label;
  final String? subtitle;
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
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
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
