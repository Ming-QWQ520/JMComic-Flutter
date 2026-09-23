import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/protocol/jm_api.dart';
import '../core/protocol/models.dart';
import '../core/utils/scramble.dart';

/// 下载任务状态。
enum DownloadStatus { waiting, running, paused, done, error }

/// 单章下载任务（对齐 qt download_item）。
class DownloadTask extends ChangeNotifier {
  DownloadTask({
    required this.albumId,
    required this.albumName,
    required this.epsId,
    required this.epsName,
    required this.imageUrls,
    required this.scrambleId,
  });

  final String albumId;
  final String albumName;
  final String epsId;
  final String epsName;
  final List<String> imageUrls;
  final int scrambleId;

  int completed = 0;
  DownloadStatus status = DownloadStatus.waiting;
  String error = '';

  double get progress =>
      imageUrls.isEmpty ? 0 : completed / imageUrls.length;

  bool get isDone => status == DownloadStatus.done;

  void tick() {
    completed++;
    notifyListeners();
  }

  void setStatus(DownloadStatus s, [String msg = '']) {
    status = s;
    error = msg;
    notifyListeners();
  }
}

/// 本地下载管理器（对齐 tonquer/JMComic-qt 下载体系）。
///
/// - 目录结构：{documents}/commics/{albumId}/{epsId}/{index}.jpg（对齐 qt SavePathDir）；
/// - 并发下载数（对齐 qt DownloadThreadNum = 5）；
/// - 下载后自动乱序还原为可直读图片（对齐 qt SegmentationPictureToDisk）；
/// - 支持暂停/继续/删除与本地离线阅读。
class DownloadManager extends ChangeNotifier {
  DownloadManager._internal();
  static final DownloadManager instance = DownloadManager._internal();

  final List<DownloadTask> tasks = <DownloadTask>[];

  /// 并发下载数（对齐 qt config.DownloadThreadNum）。
  int concurrent = 5;

  bool _running = false;
  Directory? _baseDir;

  Future<Directory> baseDir() async {
    if (_baseDir != null) return _baseDir!;
    final docs = await getApplicationDocumentsDirectory();
    _baseDir = Directory('${docs.path}/commics');
    if (!_baseDir!.existsSync()) _baseDir!.createSync(recursive: true);
    return _baseDir!;
  }

  /// 某章节是否已完整下载。
  Future<bool> isDownloaded(String albumId, String epsId) async {
    final meta = await _readMeta(albumId, epsId);
    if (meta == null) return false;
    return (meta['done'] as bool? ?? false);
  }

  /// 列出已下载章节元信息。
  Future<Map<String, dynamic>?> _readMeta(String albumId, String epsId) async {
    try {
      final dir = await baseDir();
      final f = File('${dir.path}/$albumId/$epsId/meta.json');
      if (!f.existsSync()) return null;
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 读取本地章节图片文件列表（本地离线阅读）。
  Future<List<File>> localImages(String albumId, String epsId) async {
    final meta = await _readMeta(albumId, epsId);
    if (meta == null) return <File>[];
    final dir = await baseDir();
    final epsDir = Directory('${dir.path}/$albumId/$epsId');
    if (!epsDir.existsSync()) return <File>[];
    final n = meta['total'] as int? ?? 0;
    final out = <File>[];
    for (var i = 0; i < n; i++) {
      final f = File('${epsDir.path}/$i.jpg');
      if (f.existsSync()) out.add(f);
    }
    return out;
  }

  /// 添加整本下载（全部章节，对齐 qt download_all_view）。
  Future<void> addAlbum({
    required String albumId,
    required String albumName,
    required List<SeriesItem> series,
  }) async {
    for (final eps in series) {
      await addEps(
        albumId: albumId,
        albumName: albumName,
        epsId: eps.id,
        epsName: eps.name.isEmpty ? '第${eps.sort}话' : eps.name,
      );
    }
  }

  /// 添加单章下载（对齐 qt download_some_view）。
  ///
  /// 拉取章节图片列表后入队，由调度器按并发数执行。
  Future<void> addEps({
    required String albumId,
    required String albumName,
    required String epsId,
    required String epsName,
  }) async {
    // 已下载/已在队列则跳过
    if (await isDownloaded(albumId, epsId)) return;
    if (tasks.any((t) => t.albumId == albumId && t.epsId == epsId)) return;

    try {
      final read = await JmApi.instance.getComicRead(epsId);
      var sid = int.tryParse(read.scrambleId) ?? 0;
      if (sid == 0) {
        try {
          sid = await JmApi.instance.getScrambleId(epsId);
        } catch (_) {}
      }
      final urls = read.images.map((e) => e.image).toList();
      if (urls.isEmpty) return;
      final task = DownloadTask(
        albumId: albumId,
        albumName: albumName,
        epsId: epsId,
        epsName: epsName,
        imageUrls: urls,
        scrambleId: sid,
      );
      tasks.add(task);
      notifyListeners();
      _schedule();
    } catch (_) {
      rethrow;
    }
  }

  void pause(DownloadTask task) {
    if (task.status == DownloadStatus.running ||
        task.status == DownloadStatus.waiting) {
      task.setStatus(DownloadStatus.paused);
      notifyListeners();
    }
  }

  void resume(DownloadTask task) {
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.error) {
      task.setStatus(DownloadStatus.waiting);
      notifyListeners();
      _schedule();
    }
  }

  Future<void> remove(DownloadTask task) async {
    task.setStatus(DownloadStatus.paused);
    tasks.remove(task);
    // 删除本地半成品
    try {
      final dir = await baseDir();
      final epsDir = Directory('${dir.path}/${task.albumId}/${task.epsId}');
      if (epsDir.existsSync()) epsDir.deleteSync(recursive: true);
    } catch (_) {}
    notifyListeners();
  }

  void _schedule() {
    if (_running) return;
    _running = true;
    _pump();
  }

  Future<void> _pump() async {
    while (true) {
      final waiting =
          tasks.where((t) => t.status == DownloadStatus.waiting).toList();
      if (waiting.isEmpty) {
        _running = false;
        return;
      }
      // 并发执行（对齐 qt 多线程下载）
      final batch = waiting.take(concurrent).toList();
      await Future.wait(batch.map(_runTask));
      // 清理已完成任务留在列表（供查看），不自动移除
    }
  }

  Future<void> _runTask(DownloadTask task) async {
    task.setStatus(DownloadStatus.running);
    try {
      final dir = await baseDir();
      final epsDir = Directory('${dir.path}/${task.albumId}/${task.epsId}');
      if (!epsDir.existsSync()) epsDir.createSync(recursive: true);
      final aid = int.tryParse(task.albumId) ?? 0;
      final needScramble = Scramble.needScramble(aid, task.scrambleId);

      for (var i = task.completed; i < task.imageUrls.length; i++) {
        if (task.status == DownloadStatus.paused) return;
        final url = task.imageUrls[i];
        final raw = await JmApi.instance.downloadImage(url);
        Uint8List bytes = Uint8List.fromList(raw);
        final isGif = url.toLowerCase().endsWith('.gif');
        if (needScramble && !isGif) {
          final name = Scramble.filenameFromUrl(url);
          try {
            bytes = await Scramble.descramble(bytes, task.albumId, name);
          } catch (_) {
            // 还原失败用原图
          }
        }
        final f = File('${epsDir.path}/$i.jpg');
        await f.writeAsBytes(bytes, flush: true);
        task.tick();
      }
      final meta = <String, dynamic>{
        'albumId': task.albumId,
        'albumName': task.albumName,
        'epsId': task.epsId,
        'epsName': task.epsName,
        'total': task.imageUrls.length,
        'done': true,
        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
      await File('${epsDir.path}/meta.json')
          .writeAsString(jsonEncode(meta), flush: true);
      task.setStatus(DownloadStatus.done);
      notifyListeners();
    } catch (e) {
      task.setStatus(DownloadStatus.error, e.toString());
      notifyListeners();
    }
  }
}
