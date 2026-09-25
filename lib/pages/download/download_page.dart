import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/download_manager.dart';
import '../../services/storage_service.dart';
import '../../widgets/feedback.dart';

/// 下载任务状态展示模型辅助。
extension DownloadTaskX on DownloadTask {
  String statusLabel(ColorScheme cs) => switch (status) {
        DownloadStatus.waiting => '等待',
        DownloadStatus.running => '下载中',
        DownloadStatus.paused => '已暂停',
        DownloadStatus.done => '完成',
        DownloadStatus.error => '失败',
      };

  /// 多选模式的唯一键。
  String get selectKey => '$albumId::$epsId';
}

/// 下载管理页（对齐 qt DownloadView）。
///
/// 展示下载任务队列（进度/暂停/继续/删除），支持点击已完成章节离线阅读；
/// 长按任意任务进入多选模式，可批量暂停/继续/删除；
/// 右上角可调用系统文件管理器打开下载文件夹。
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final DownloadManager mgr = DownloadManager.instance;

  /// 多选模式与已选任务（key = albumId::epsId）。
  bool _selectMode = false;
  final Set<String> _selected = <String>{};

  void _toggleSelect(DownloadTask t) {
    final key = t.selectKey;
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _enterSelectMode(DownloadTask t) {
    setState(() {
      _selectMode = true;
      _selected.add(t.selectKey);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _selectAll(List<DownloadTask> tasks) {
    setState(() {
      if (_selected.length == tasks.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(tasks.map((t) => t.selectKey));
      }
    });
  }

  Future<void> _batchDelete(List<DownloadTask> tasks) async {
    final targets =
        tasks.where((t) => _selected.contains(t.selectKey)).toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除选中的 ${targets.length} 个任务吗？\n未完成的本地文件将一并删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final t in targets) {
      await mgr.remove(t);
    }
    _exitSelectMode();
  }

  void _batch(List<DownloadTask> tasks, void Function(DownloadTask) op) {
    for (final t in tasks) {
      if (_selected.contains(t.selectKey)) op(t);
    }
    _exitSelectMode();
  }

  /// 调用系统文件管理器打开下载根目录。
  Future<void> _openDownloadFolder() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await mgr.baseDir();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // 公共目录场景下未授权时文件管理器也看不到内容，先确保权限
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _selectMode) _exitSelectMode();
      },
      child: Scaffold(
        appBar: _selectMode
            ? AppBar(
                leading: IconButton(
                  tooltip: '退出多选',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _exitSelectMode,
                ),
                title: Text('已选 ${_selected.length} 项'),
                actions: <Widget>[
                  ListenableBuilder(
                    listenable: mgr,
                    builder: (BuildContext c, _) {
                      final tasks = mgr.tasks;
                      return IconButton(
                        tooltip: _selected.length == tasks.length
                            ? '取消全选'
                            : '全选',
                        icon: Icon(
                          _selected.length == tasks.length
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                        ),
                        onPressed: () => _selectAll(tasks),
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: mgr,
                    builder: (BuildContext c, _) {
                      final tasks = mgr.tasks;
                      final sel =
                          tasks.where((t) => _selected.contains(t.selectKey));
                      final canPause = sel.any(
                        (t) =>
                            t.status == DownloadStatus.running ||
                            t.status == DownloadStatus.waiting,
                      );
                      final canResume = sel.any(
                        (t) =>
                            t.status == DownloadStatus.paused ||
                            t.status == DownloadStatus.error,
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: '暂停',
                            icon: const Icon(Icons.pause_circle_outline_rounded),
                            onPressed: canPause
                                ? () => _batch(
                                    mgr.tasks, (t) => mgr.pause(t))
                                : null,
                          ),
                          IconButton(
                            tooltip: '继续',
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            onPressed: canResume
                                ? () => _batch(
                                    mgr.tasks, (t) => mgr.resume(t))
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => _batchDelete(mgr.tasks),
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                title: const Text('下载管理'),
                actions: <Widget>[
                  IconButton(
                    tooltip: '打开下载文件夹',
                    icon: const Icon(Icons.folder_open_rounded),
                    onPressed: _openDownloadFolder,
                  ),
                  IconButton(
                    tooltip: '本地书架',
                    icon: const Icon(Icons.folder_rounded),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const LocalLibraryPage()),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
        body: ListenableBuilder(
          listenable: mgr,
          builder: (BuildContext context, _) {
            if (mgr.tasks.isEmpty) {
              return const EmptyView(message: '暂无下载任务\n在漫画详情页点击下载按钮添加');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: mgr.tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = mgr.tasks[i];
                return _TaskCard(
                  task: t,
                  cs: cs,
                  tt: tt,
                  mgr: mgr,
                  selectMode: _selectMode,
                  selected: _selected.contains(t.selectKey),
                  onLongPress: () => _enterSelectMode(t),
                  onSelectToggle: () => _toggleSelect(t),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.cs,
    required this.tt,
    required this.mgr,
    required this.selectMode,
    required this.selected,
    required this.onLongPress,
    required this.onSelectToggle,
  });

  final DownloadTask task;
  final ColorScheme cs;
  final TextTheme tt;
  final DownloadManager mgr;
  final bool selectMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onSelectToggle;

  Color get _statusColor => switch (task.status) {
        DownloadStatus.waiting => cs.onSurfaceVariant,
        DownloadStatus.running => cs.primary,
        DownloadStatus.paused => Colors.orange,
        DownloadStatus.done => Colors.green,
        DownloadStatus.error => cs.error,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 多选模式下点击 = 勾选；长按任意卡片进入多选模式。
        onTap: selectMode ? onSelectToggle : null,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (selectMode) ...<Widget>[
                    Icon(
                      selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 22,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.albumName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${task.epsName} · ${task.completed}/${task.imageUrls.length} 张',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      task.statusLabel(cs),
                      style: TextStyle(
                          fontSize: 11,
                          color: _statusColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!selectMode)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (String v) {
                        switch (v) {
                          case 'pause':
                            mgr.pause(task);
                          case 'resume':
                            mgr.resume(task);
                          case 'delete':
                            mgr.remove(task);
                        }
                      },
                      itemBuilder: (_) => <PopupMenuItem<String>>[
                        if (task.status == DownloadStatus.running ||
                            task.status == DownloadStatus.waiting)
                          const PopupMenuItem<String>(
                              value: 'pause', child: Text('暂停')),
                        if (task.status == DownloadStatus.paused ||
                            task.status == DownloadStatus.error)
                          const PopupMenuItem<String>(
                              value: 'resume', child: Text('继续')),
                        const PopupMenuItem<String>(
                            value: 'delete', child: Text('删除任务')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  backgroundColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.6),
                ),
              ),
              if (task.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(task.error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(color: cs.error)),
                ),
              if (!selectMode && task.isDone)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _readLocal(context),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('离线阅读'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 本地离线阅读（对齐 qt local_read_view）。
  Future<void> _readLocal(BuildContext context) async {
    final files =
        await DownloadManager.instance.localImages(task.albumId, task.epsId);
    if (!context.mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地文件缺失')));
      return;
    }
    Navigator.pushNamed(context, '/local_reader', arguments: <String, dynamic>{
      'title': '${task.albumName} · ${task.epsName}',
      'files': files.map((File f) => f.path).toList(),
    });
  }
}

/// 本地章节条目。
class LocalChapter {
  LocalChapter({
    required this.albumId,
    required this.epsId,
    required this.albumName,
    required this.epsName,
    required this.total,
  });

  final String albumId;
  final String epsId;
  final String albumName;
  final String epsName;
  final int total;
}

/// 已下载章节列表页（本地书架，对齐 qt local_read_view）。
class LocalLibraryPage extends StatefulWidget {
  const LocalLibraryPage({super.key});

  @override
  State<LocalLibraryPage> createState() => _LocalLibraryPageState();
}

class _LocalLibraryPageState extends State<LocalLibraryPage> {
  final List<LocalChapter> _chapters = <LocalChapter>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _basename(FileSystemEntity e) => e.path.split(Platform.pathSeparator).last;

  Future<void> _load() async {
    final items = <LocalChapter>[];
    try {
      final dir = await DownloadManager.instance.baseDir();
      final albums = dir.listSync().whereType<Directory>();
      for (final a in albums) {
        // 注意：Directory.uri 的 pathSegments 末尾恒为空串，
        // 此前用 uri.pathSegments.last 会得到空 albumId（本地书架
        // 全部显示空名且离线阅读报"本地文件缺失"），改用路径切分。
        final albumId = _basename(a);
        if (albumId.isEmpty) continue;
        // 新目录结构：无章节漫画的 meta.json 与图片直接位于专辑目录下。
        final albumMeta = File('${a.path}/meta.json');
        if (albumMeta.existsSync()) {
          final meta = _safeJson(albumMeta);
          if (meta != null) {
            items.add(LocalChapter(
              albumId: albumId,
              epsId: albumId,
              albumName: meta['albumName']?.toString() ?? '',
              epsName: meta['epsName']?.toString() ?? '全本',
              total: meta['total'] as int? ?? 0,
            ));
            continue;
          }
        }
        // 多章节漫画：专辑目录下为章节子目录。
        final epses = a.listSync().whereType<Directory>();
        for (final e in epses) {
          final metaFile = File('${e.path}/meta.json');
          if (!metaFile.existsSync()) continue;
          final meta = _safeJson(metaFile);
          if (meta == null) continue;
          items.add(LocalChapter(
            albumId: albumId,
            epsId: _basename(e),
            albumName: meta['albumName']?.toString() ?? '',
            epsName: meta['epsName']?.toString() ?? '',
            total: meta['total'] as int? ?? 0,
          ));
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _chapters
        ..clear()
        ..addAll(items);
      _loading = false;
    });
  }

  Map<String, dynamic>? _safeJson(File f) {
    try {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地书架'),
        actions: <Widget>[
          IconButton(
            tooltip: '打开下载文件夹',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () async {
              try {
                final dir = await DownloadManager.instance.baseDir();
                final ok = await StorageService.openFolder(dir.path);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('未找到可用的文件管理器，请手动前往：${dir.path}'),
                  ));
                }
              } catch (_) {}
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _chapters.isEmpty
              ? const EmptyView(message: '还没有已下载的章节')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: _chapters.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _chapters[i];
                      return Card(
                        child: ListTile(
                          leading: Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.menu_book_rounded,
                                size: 20, color: cs.primary),
                          ),
                          title: Text(c.albumName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${c.epsName} · ${c.total} 张',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 20, color: cs.onSurfaceVariant),
                            onPressed: () => _delete(c),
                          ),
                          onTap: () => _read(c),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _read(LocalChapter c) async {
    final files =
        await DownloadManager.instance.localImages(c.albumId, c.epsId);
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地文件缺失')));
      return;
    }
    Navigator.pushNamed(context, '/local_reader', arguments: <String, dynamic>{
      'title': '${c.albumName} · ${c.epsName}',
      'files': files.map((File f) => f.path).toList(),
    });
  }

  Future<void> _delete(LocalChapter c) async {
    final mgr = DownloadManager.instance;
    try {
      final dir = await mgr.baseDir();
      final epsDir = Directory(mgr.epsDirPath(dir, c.albumId, c.epsId));
      if (epsDir.existsSync()) epsDir.deleteSync(recursive: true);
    } catch (_) {}
    _load();
  }
}
