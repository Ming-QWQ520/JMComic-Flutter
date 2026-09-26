import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/protocol/jm_domain.dart';
import '../../services/download_manager.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';
import '../user/about_page.dart';

/// 设置页（对齐 tonquer/JMComic-qt SettingView）。
///
/// 分组：主题配色（6 套，紧凑布局）、线路选择（API/图片 + 测速）、
/// DoH、阅读设置（方向/音量键/常亮/预加载）、个性化（自定义背景 +
/// 透明度滑杆）、其他（清缓存）。
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
          // ---------- 主题（紧凑横排 Grid，不再每套一行） ----------
          SectionHeader(title: '主题配色'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: _ThemeGrid(
                value: state.scheme,
                onChanged: (ThemeScheme? v) {
                  if (v != null) state.setScheme(v);
                },
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
                              subtitle: _speedSubtitle(context, state, e.key),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 翻页方向：使用 SegmentedButton + 标签置于按钮上方，
                  // 修复"上下/左右"模式下文字位置偏差（此前 Padding 不对称，
                  // 短文本居左对齐时与下方按钮错位）。
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('翻页方向',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ReadDirection>(
                            // 全宽 SegmentedButton：每段等宽，标签居中，
                            // 短/长标签对齐一致。
                            style: SegmentedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                            ),
                            segments:
                                const <ButtonSegment<ReadDirection>>[
                              ButtonSegment<ReadDirection>(
                                  value: ReadDirection.vertical,
                                  label: Text('上下')),
                              ButtonSegment<ReadDirection>(
                                  value: ReadDirection.horizontal,
                                  label: Text('左右')),
                              ButtonSegment<ReadDirection>(
                                  value: ReadDirection.rightToLeft,
                                  label: Text('从右至左')),
                            ],
                            selected: <ReadDirection>{state.readDirection},
                            onSelectionChanged: (Set<ReadDirection> s) =>
                                state.setReadDirection(s.first),
                          ),
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
                          ? DownloadManager.instance.defaultBase
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
          // ---------- 个性化（自定义背景 + 透明度滑杆） ----------
          SectionHeader(title: '个性化'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: <Widget>[
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.wallpaper_rounded,
                        size: 20, color: cs.primary),
                    title: const Text('自定义背景'),
                    subtitle: Text(
                      state.hasCustomBackground
                          ? '已设置（应用于除阅读器外的所有页面）'
                          : '未设置，使用默认主题背景',
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => _pickBackground(context, state),
                  ),
                  // 自定义背景透明度（仅当设置了背景时显示）。
                  // 滑杆布局重设计：去除提示副标题，滑杆放在名称下方
                  // 占整行宽度，调节更顺手。
                  if (state.hasCustomBackground) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.opacity_rounded,
                              size: 20, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('背景透明度',
                                style: tt.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          Text(
                            '${(state.backgroundOpacity * 100).round()}%',
                            style: tt.labelMedium
                                ?.copyWith(color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
                      child: Slider(
                        min: 0,
                        max: 100,
                        divisions: 100,
                        value: (state.backgroundOpacity * 100)
                            .round()
                            .toDouble(),
                        onChanged: (double v) =>
                            state.setBackgroundOpacity(v / 100.0),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.restart_alt_rounded,
                          size: 20, color: cs.primary),
                      title: const Text('恢复默认背景'),
                      onTap: () async {
                        await state.setBackground('');
                        // 关键修复：Windows 端"恢复默认背景后再设置会显示
                        // 第一次设置的图片背景"——根因是旧图片文件残留于
                        // 应用文档目录，恢复默认后未删除原文件，下次设置时
                        // 仍是同一路径写入新字节，但 Image.file 缓存命中旧
                        // 解码结果。这里在恢复默认时直接删除残留文件，避免
                        // 下次设置时缓存命中。
                        try {
                          final docs =
                              await getApplicationDocumentsDirectory();
                          final old =
                              File('${docs.path}/custom_background.img');
                          if (old.existsSync()) await old.delete();
                        } catch (_) {}
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已恢复默认背景')));
                      },
                    ),
                  ],
                  // 选项透明度：与背景透明度独立。控制前景 UI 元素
                  // （卡片/底栏/列表项/弹窗/筛选按钮）的半透明程度。
                  // 即使未设置自定义背景也可调（默认 100% 完全不透明）。
                  // 滑杆布局重设计：去除提示副标题，滑杆放在名称下方
                  // 占整行宽度；范围 10~100（最低 10% 避免前景完全透明）。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tune_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('选项透明度',
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          '${(state.cardOpacity * 100).round()}%',
                          style: tt.labelMedium?.copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                    child: Slider(
                      min: 10,
                      max: 100,
                      divisions: 90,
                      value: (state.cardOpacity * 100).round().toDouble(),
                      onChanged: (double v) =>
                          state.setCardOpacity(v / 100.0),
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
                    subtitle: const Text('删除全部已下载章节（不影响收藏与自定义背景）'),
                    onTap: () => _clearDownloads(context),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline_rounded, size: 20),
                    title: const Text('关于'),
                    subtitle: const Text(
                        '项目介绍 / 作者 / 相关链接'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const AboutPage()),
                    ),
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

  /// 翻页方向测速结果子标题：固定宽度对齐，避免短文本"不可用 / 12 ms"
  /// 切换时位置偏差。
  Widget? _speedSubtitle(
    BuildContext context,
    AppState state,
    int idx,
  ) {
    final v = state.speedResults[idx.toString()];
    if (v == null) return null;
    final cs = Theme.of(context).colorScheme;
    final String text = v < 0 ? '不可用' : '$v ms';
    final Color color = v < 0 ? cs.error : Colors.green;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: color,
        // 使用等宽字体，避免短/长文本切换时位置漂移。
        fontFamily: 'monospace',
      ),
    );
  }

  /// 选择并保存自定义背景图（应用于除漫画阅读器外的所有页面）。
  Future<void> _pickBackground(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Windows/Android 通用：mimeTypes + extensions 双条件，
      // 兼容不同平台文件对话框的过滤实现。
      XFile? picked;
      try {
        picked = await openFile(
          acceptedTypeGroups: <XTypeGroup>[
            const XTypeGroup(
              label: '图片',
              mimeTypes: <String>['image/png', 'image/jpeg', 'image/webp'],
              extensions: <String>['png', 'jpg', 'jpeg', 'webp'],
            ),
          ],
        );
      } catch (_) {
        // 部分平台/版本 openFile 可能不可用：回退到任意文件选择。
        picked = await openFile();
      }
      final XFile? file = picked;
      if (file == null) return;
      // 选择器返回的是临时缓存路径（Android SAF 副本），
      // 复制进应用文档目录确保持久可用。文件名加时间戳避免 Image
      // 缓存命中旧解码（修复 Windows 端"恢复默认背景后再设置显示
      // 第一次背景"bug——同路径不同字节会被 Image.file 缓存命中）。
      final docs = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final target = File('${docs.path}/custom_background_$stamp.img');
      final bytes = await File(file.path).readAsBytes();
      if (bytes.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('所选文件为空，请重新选择图片')));
        return;
      }
      await target.writeAsBytes(bytes);
      // 删除所有旧的背景缓存文件，确保只有一个生效。
      try {
        final entities = docs.listSync();
        for (final e in entities) {
          if (e is File &&
              e.path.contains('custom_background') &&
              e.path != target.path) {
            await e.delete();
          }
        }
      } catch (_) {}
      // 先解码验证（Windows 上失败要立刻给出可读原因，而不是
      // 静默落到 errorBuilder 的"设置成功但看不见背景"）。
      if (!context.mounted) return;
      try {
        await precacheImage(
          FileImage(target),
          context,
          onError: (Object e, StackTrace? st) => throw e,
        );
      } catch (e) {
        try {
          target.deleteSync();
        } catch (_) {}
        messenger.showSnackBar(SnackBar(
          content: Text('图片解码失败，请换一张图片（$e）'),
        ));
        return;
      }
      await state.setBackground(target.path);
      messenger.showSnackBar(
          const SnackBar(content: Text('背景已更新，应用于除阅读器外的所有页面')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('设置背景失败：$e')));
    }
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

  /// 修改下载根目录（Android 默认公共下载目录，桌面端默认文档目录；
  /// 可在设置中修改；留空恢复默认）。
  Future<void> _editDownloadDir(BuildContext context, AppState state) async {
    final ctrl = TextEditingController(
      text: state.downloadDir.isEmpty
          ? DownloadManager.instance.defaultBase
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
            const SizedBox(height: 10),
            // 系统文件夹选择器（Android SAF / Windows 原生对话框），
            // 选完自动回填路径，免手动输入。
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    final dir = await getDirectoryPath(
                      confirmButtonText: '选择此文件夹',
                    );
                    if (dir != null && c.mounted) {
                      ctrl.text = dir;
                    }
                  } catch (_) {
                    // 当前平台不支持目录选择时静默（可手动输入）
                  }
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('选择文件夹…'),
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
  ///
  /// 关键修复：打开前绝不做存储权限检查/申请——那会把用户带去系统
  /// 设置页，表现为"点打开没反应/不正常调用"。文件管理器读取公共
  /// 目录靠其自身权限，与 APP 的授权状态无关。
  Future<void> _openDownloadFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await DownloadManager.instance.baseDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
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

  /// 清理下载缓存。修复：原实现会删除 baseDir 整树，但 baseDir
  /// 路径与"应用文档目录"在 Android 上不同分区，绝不会误伤
  /// `custom_background.img` 等自定义背景文件。但部分用户自定义背景
  /// 路径若指向下载目录子目录，删除后会让背景文件丢失。
  /// 这里仅删除每个 [漫画号] 子目录，保留 baseDir 本身。
  Future<void> _clearDownloads(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('清理下载缓存'),
        content: const Text('确定删除全部已下载的章节图片吗？\n'
            '（不会影响收藏、登录态与自定义背景）'),
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
      if (dir.existsSync()) {
        // 仅删除子目录（漫画号文件夹），保留 baseDir 自身。
        for (final e in dir.listSync()) {
          if (e is Directory) {
            try {
              await e.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清理')));
  }
}

/// 主题配色紧凑网格：6 套主题以 3 列 × 2 行的圆点 + 标签呈现，
/// 替代原来 6 行 RadioListTile（节省垂直空间，主题配色区域从
/// ~480px 高降到 ~180px 高，不影响触摸目标大小）。
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.value, required this.onChanged});

  final ThemeScheme value;
  final ValueChanged<ThemeScheme?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: <Widget>[
        for (final s in ThemeScheme.values)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(s),
            child: Container(
              decoration: BoxDecoration(
                color: value == s
                    ? cs.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: value == s
                    ? Border.all(color: cs.primary, width: 1.4)
                    : null,
              ),
              padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: SchemeColors.of(s).primary,
                      shape: BoxShape.circle,
                      boxShadow: value == s
                          ? <BoxShadow>[
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.3),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          value == s ? FontWeight.w700 : FontWeight.w500,
                      color: value == s ? cs.primary : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
