import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/protocol/jm_domain.dart';
import '../../services/download_manager.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 设置页（对齐 tonquer/JMComic-qt SettingView）。
///
/// 分组：主题配色（6 套）、线路选择（API/图片 + 测速）、DoH、
/// 阅读设置（方向/音量键/常亮/预加载）、其他（清缓存）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ---------- 主题 ----------
          SectionHeader(title: '主题配色'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RadioGroup<ThemeScheme>(
                groupValue: state.scheme,
                onChanged: (ThemeScheme? v) {
                  if (v != null) state.setScheme(v);
                },
                child: Column(
                  children: <Widget>[
                    for (final s in ThemeScheme.values)
                      RadioListTile<ThemeScheme>(
                        value: s,
                        title: Text(s.label),
                        secondary: _colorDot(SchemeColors.of(s).primary),
                        dense: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 线路 ----------
          SectionHeader(title: '线路选择'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('API 线路', style: tt.titleSmall),
                  const SizedBox(height: 6),
                  RadioGroup<int>(
                    groupValue: state.apiIndex,
                    onChanged: (int? v) {
                      if (v != null) state.setApiIndex(v);
                    },
                    child: Column(
                      children: _apiOptions()
                          .map(
                            (MapEntry<int, String> e) => RadioListTile<int>(
                              value: e.key,
                              title: Text(e.value),
                              subtitle:
                                  state.speedResults[e.value] != null
                                      ? Text(
                                          state.speedResults[e.value]! < 0
                                              ? '不可用'
                                              : '${state.speedResults[e.value]} ms',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: (state.speedResults[e.value] ??
                                                        -1) <
                                                    0
                                                ? cs.error
                                                : Colors.green,
                                          ))
                                      : null,
                              dense: true,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed:
                          state.speedTesting ? null : state.testApiSpeed,
                      icon: state.speedTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.speed_rounded, size: 18),
                      label: const Text('线路测速'),
                    ),
                  ),
                  const Divider(),
                  Text('图片线路', style: tt.titleSmall),
                  const SizedBox(height: 6),
                  RadioGroup<int>(
                    groupValue: state.imgIndex,
                    onChanged: (int? v) {
                      if (v != null) state.setImgIndex(v);
                    },
                    child: Column(
                      children: _imgOptions()
                          .map(
                            (MapEntry<int, String> e) => RadioListTile<int>(
                              value: e.key,
                              title: Text(e.value),
                              dense: true,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- DoH ----------
          SectionHeader(title: 'DoH 加密解析'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    value: state.enableDoh,
                    onChanged: (bool v) => state.setEnableDoh(v),
                    title: const Text('启用 DoH'),
                    subtitle: const Text('绕过 DNS 污染，网络异常时可尝试开启'),
                    dense: true,
                  ),
                  if (state.enableDoh)
                    RadioGroup<int>(
                      groupValue: state.dohIndex + 1,
                      onChanged: (int? v) {
                        if (v != null) state.setDohIndex(v - 1);
                      },
                      child: Column(
                        children: <Widget>[
                          for (var i = 0;
                              i < JmDomain.dohUrlList.value.length;
                              i++)
                            RadioListTile<int>(
                              value: i + 1,
                              title: Text(Uri.parse(
                                      JmDomain.dohUrlList.value[i])
                                  .host),
                              dense: true,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 阅读 ----------
          SectionHeader(title: '阅读设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  // 翻页方向（对齐 qt ReadView 方向）
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('翻页方向'),
                        const SizedBox(height: 8),
                        SegmentedButton<ReadDirection>(
                          segments: const <ButtonSegment<ReadDirection>>[
                            ButtonSegment<ReadDirection>(
                                value: ReadDirection.vertical,
                                label: Text('上下')),
                            ButtonSegment<ReadDirection>(
                                value: ReadDirection.horizontal,
                                label: Text('左右')),
                            ButtonSegment<ReadDirection>(
                                value: ReadDirection.rightToLeft,
                                label: Text('日漫')),
                          ],
                          selected: <ReadDirection>{state.readDirection},
                          onSelectionChanged: (Set<ReadDirection> s) =>
                              state.setReadDirection(s.first),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    value: state.volumeKeyPaging,
                    onChanged: (bool v) => state.setVolumeKeyPaging(v),
                    title: const Text('音量键翻页'),
                    dense: true,
                  ),
                  SwitchListTile(
                    value: state.keepScreenOn,
                    onChanged: (bool v) => state.setKeepScreenOn(v),
                    title: const Text('阅读时屏幕常亮'),
                    dense: true,
                  ),
                  // 预加载页数（对齐 qt PreLoading）
                  ListTile(
                    dense: true,
                    title: const Text('预加载页数'),
                    trailing: SizedBox(
                      width: 160,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Slider(
                              min: 1,
                              max: 10,
                              divisions: 9,
                              value: state.preLoad.toDouble(),
                              onChanged: (double v) =>
                                  state.setPreLoad(v.round()),
                            ),
                          ),
                          SizedBox(
                              width: 26,
                              child: Text('${state.preLoad}',
                                  textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 下载 ----------
          SectionHeader(title: '下载设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.folder_open_rounded,
                        size: 20, color: cs.primary),
                    title: const Text('下载位置'),
                    subtitle: Text(
                      state.downloadDir.isEmpty
                          ? (DownloadManager.androidDefaultBase)
                          : state.downloadDir,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => _editDownloadDir(context, state),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.folder_special_rounded,
                        size: 20, color: cs.primary),
                    title: const Text('打开下载文件夹'),
                    subtitle: const Text('调用系统文件管理器浏览已下载内容'),
                    onTap: () => _openDownloadFolder(context),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.sd_storage_rounded,
                        size: 20, color: cs.primary),
                    title: const Text('存储权限'),
                    subtitle: const Text('下载到公共目录需要"所有文件访问"权限'),
                    trailing: TextButton(
                      onPressed: () => _ensureStorage(context),
                      child: const Text('检查/授予'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 其他 ----------
          SectionHeader(title: '其他'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.image_outlined,
                        size: 20, color: cs.primary),
                    title: const Text('清理图片缓存'),
                    subtitle: const Text('封面/头像的内存与磁盘缓存'),
                    onTap: () => _clearImageCache(context),
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.cleaning_services_rounded,
                        size: 20, color: cs.primary),
                    title: const Text('清理下载缓存'),
                    subtitle: const Text('删除全部已下载章节（不影响收藏）'),
                    onTap: () => _clearDownloads(context),
                  ),
                  const ListTile(
                    dense: true,
                    leading: Icon(Icons.info_outline_rounded, size: 20),
                    title: Text('关于'),
                    subtitle: Text(
                        'JMComic-Flutter v2.1.0\nAPI 协议对齐 tonquer/JMComic-qt'),
                    isThreeLine: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<MapEntry<int, String>> _apiOptions() {
    final list = JmDomain.apiUrlList.value;
    final out = <MapEntry<int, String>>[];
    for (var i = 0; i < list.length; i++) {
      out.add(MapEntry<int, String>(i + 1, Uri.parse(list[i]).host));
    }
    out.add(const MapEntry<int, String>(5, 'CDN 加速线路'));
    out.add(const MapEntry<int, String>(6, '代理线路'));
    return out;
  }

  List<MapEntry<int, String>> _imgOptions() {
    final list = JmDomain.picUrlList.value;
    final out = <MapEntry<int, String>>[];
    for (var i = 0; i < list.length; i++) {
      out.add(MapEntry<int, String>(i + 1, Uri.parse(list[i]).host));
    }
    out.add(const MapEntry<int, String>(5, 'CDN 加速线路'));
    out.add(const MapEntry<int, String>(6, '代理线路'));
    return out;
  }

  Widget _colorDot(Color c) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
        ),
      );

  /// 修改下载根目录（对齐需求：默认 /storage/emulated/0/Download/JM-Flutter，
  /// 可在设置中修改；留空恢复默认）。
  Future<void> _editDownloadDir(BuildContext context, AppState state) async {
    final ctrl = TextEditingController(
      text: state.downloadDir.isEmpty
          ? DownloadManager.androidDefaultBase
          : state.downloadDir,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('下载位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('下载内容将保存到该目录下的 [漫画号] 子文件夹中。'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '目录路径',
                hintText: '/storage/emulated/0/Download/JM-Flutter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ctrl.clear();
            },
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    // 恢复默认 = 文本框被清空。
    final path = ctrl.text.trim();
    await state.setDownloadDir(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path.isEmpty
          ? '已恢复默认下载位置'
          : '下载位置已保存：$path'),
    ));
  }

  /// 打开下载文件夹（系统文件管理器）。
  Future<void> _openDownloadFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await DownloadManager.instance.baseDir();
      if (!await StorageService.hasStorage()) {
        await StorageService.ensureStorage();
      }
      final ok = await StorageService.openFolder(dir.path);
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text('未找到可用的文件管理器，请手动前往：${dir.path}'),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('打开文件夹失败：$e')));
    }
  }

  /// 检查/申请存储权限（Android 11+ 跳转系统设置页）。
  Future<void> _ensureStorage(BuildContext context) async {
    if (!StorageService.isAndroid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前平台无需存储权限')));
      return;
    }
    final granted = await StorageService.ensureStorage();
    if (!context.mounted) return;
    if (granted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('存储权限已授予')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已在系统设置中打开授权页，请允许"所有文件访问"后返回'),
        duration: Duration(seconds: 4),
      ));
    }
  }

  Future<void> _clearImageCache(BuildContext context) async {
    await ImageStore.instance.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('图片缓存已清理')));
  }

  Future<void> _clearDownloads(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('清理下载缓存'),
        content: const Text('确定删除全部已下载的章节图片吗？'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final dir = await DownloadManager.instance.baseDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清理')));
  }
}
