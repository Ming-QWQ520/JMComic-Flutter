import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/protocol/models.dart';
import '../../services/download_manager.dart';
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
}

/// 下载管理页（对齐 qt DownloadView）。
///
/// 展示下载任务队列（进度/暂停/继续/删除），支持点击已完成章节离线阅读。
class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mgr = DownloadManager.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '本地书架',
            icon: const Icon(Icons.folder_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const LocalLibraryPage()),
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
              return _TaskCard(task: t, cs: cs, tt: tt, mgr: mgr);
            },
          );
        },
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
  });

  final DownloadTask task;
  final ColorScheme cs;
  final TextTheme tt;
  final DownloadManager mgr;

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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            if (task.isDone)
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

  Future<void> _load() async {
    final items = <LocalChapter>[];
    try {
      final dir = await DownloadManager.instance.baseDir();
      final albums = dir.listSync().whereType<Directory>();
      for (final a in albums) {
        final epses = a.listSync().whereType<Directory>();
        for (final e in epses) {
          final metaFile = File('${e.path}/meta.json');
          if (!metaFile.existsSync()) continue;
          try {
            final meta =
                jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
            items.add(LocalChapter(
              albumId: a.uri.pathSegments.last,
              epsId: e.uri.pathSegments.last,
              albumName: meta['albumName']?.toString() ?? '',
              epsName: meta['epsName']?.toString() ?? '',
              total: meta['total'] as int? ?? 0,
            ));
          } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('本地书架')),
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
      final epsDir = Directory('${dir.path}/${c.albumId}/${c.epsId}');
      if (epsDir.existsSync()) epsDir.deleteSync(recursive: true);
    } catch (_) {}
    _load();
  }
}

/// 确保未使用导入告警消除（models 用于 SeriesItem 类型提示）。
// ignore: unused_element
typedef _UnusedModelsRef = SeriesItem;
