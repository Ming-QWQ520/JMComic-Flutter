import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/protocol/jm_api.dart';
import '../core/protocol/models.dart';
import '../core/utils/scramble.dart';
import 'storage_service.dart';

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
/// - 目录结构（默认）：`/storage/emulated/0/Download/JM-Flutter/{漫画号}/{章节ID}/图片`；
///   无章节漫画（epsId == albumId）图片直接放在 `JM-Flutter/{漫画号}/` 下，
///   即用户约定的 `download/JM-Flutter/[漫画号]/图片` 形态；
/// - 下载位置可在设置中修改（持久化）；桌面/测试环境回退应用文档目录；
/// - 首次使用前自动检查/申请存储权限（详见 [StorageService]）；
/// - 并发下载数（对齐 qt DownloadThreadNum = 5）；
/// - 下载后自动乱序还原为可直读图片（对齐 qt SegmentationPictureToDisk）；
/// - 支持暂停/继续/删除与本地离线阅读。
class DownloadManager extends ChangeNotifier {
  DownloadManager._internal();
  static final DownloadManager instance = DownloadManager._internal();

  final List<DownloadTask> tasks = <DownloadTask>[];

  /// 并发下载数（对齐 qt config.DownloadThreadNum）。
  int concurrent = 5;

  /// 单任务内图片并行数（提速关键：此前单任务串行下载，
  /// 单章节漫画只有 1 个任务 → 网络吞吐利用率极低，体感很慢）。
  int imageConcurrency = 4;

  bool _running = false;
  Directory? _baseDir;

  /// 用户自定义下载根目录（设置页修改，持久化于 LocalStore）。
  String customBasePath = '';

  /// Android 默认下载位置（公共下载目录下的 JM-Flutter 文件夹）。
  static const String androidDefaultBase =
      '/storage/emulated/0/Download/JM-Flutter';

  /// 平台默认下载根目录（设置页展示用）。
  /// Windows / 桌面端在运行时解析为应用文档目录下的 JM-Flutter。
  String get defaultBase {
    if (Platform.isAndroid) return androidDefaultBase;
    if (Platform.isWindows) return r'C:\Users\<用户名>\Documents\JM-Flutter';
    return '';
  }

  /// 当前生效的下载根目录路径（解析前也可用于 UI 展示）。
  String get basePath {
    if (customBasePath.trim().isNotEmpty) return customBasePath.trim();
    if (Platform.isAndroid) return androidDefaultBase;
    return ''; // 非 Android 平台解析时回退应用文档目录
  }

  Future<Directory> baseDir() async {
    if (_baseDir != null) return _baseDir!;
    String path = basePath;
    if (path.isEmpty) {
      final docs = await getApplicationDocumentsDirectory();
      path = '${docs.path}/JM-Flutter';
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _baseDir = dir;
    return dir;
  }

  /// 设置新的下载根目录（设置页调用）。
  Future<void> setBasePath(String path) async {
    customBasePath = path.trim();
    _baseDir = null; // 下次访问重新解析
    await baseDir();
  }

  /// 章节目录：无章节漫画（epsId == albumId）图片直接放在
  /// `{base}/{albumId}/` 下；多章节漫画为 `{base}/{albumId}/{epsId}/`。
  String epsDirPath(Directory base, String albumId, String epsId) {
    final sub = (epsId.isEmpty || epsId == albumId) ? albumId : '$albumId/$epsId';
    return '${base.path}/$sub';
  }

  /// 某章节是否已完整下载。
  Future<bool> isDownloaded(String albumId, String epsId) async {
    final meta = await _readMeta(albumId, epsId);
    if (meta == null) return false;
    return (meta['done'] as bool? ?? false);
  }

  /// 读取本地章节元信息（新目录优先，兼容旧版 documents/commics 布局）。
  Future<Map<String, dynamic>?> _readMeta(
    String albumId,
    String epsId,
  ) async {
    try {
      final dir = await baseDir();
      var f = File('${epsDirPath(dir, albumId, epsId)}/meta.json');
      if (!f.existsSync()) {
        // 旧版布局兼容：{documents}/commics/{albumId}/{epsId}/meta.json
        final docs = await getApplicationDocumentsDirectory();
        f = File('${docs.path}/commics/$albumId/$epsId/meta.json');
        if (!f.existsSync()) return null;
      }
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 读取本地章节图片文件列表（本地离线阅读）。
  Future<List<File>> localImages(String albumId, String epsId) async {
    final meta = await _readMeta(albumId, epsId);
    if (meta == null) return <File>[];
    final n = meta['total'] as int? ?? 0;
    final base = await baseDir();
    final dirs = <String>[
      epsDirPath(base, albumId, epsId),
      // 旧版布局兼容
      '${base.path}/commics/$albumId/$epsId',
    ];
    final out = <File>[];
    for (final path in dirs) {
      final epsDir = Directory(path);
      if (!epsDir.existsSync()) continue;
      out.clear();
      for (var i = 0; i < n; i++) {
        final f = File('${epsDir.path}/$i.jpg');
        if (f.existsSync()) out.add(f);
      }
      if (out.isNotEmpty) return out;
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
  /// 首次使用前确保已具备存储权限（未授权时抛出可提示的异常）。
  Future<void> addEps({
    required String albumId,
    required String albumName,
    required String epsId,
    required String epsName,
  }) async {
    // 存储权限：公共目录写入前提（Android）。
    if (!await StorageService.hasStorage()) {
      final granted = await StorageService.ensureStorage();
      if (!granted) {
        throw Exception('未授予存储权限：请在系统设置中允许"所有文件访问"后重试');
      }
    }
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
      final epsDir = Directory(epsDirPath(dir, task.albumId, task.epsId));
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
      final epsDir = Directory(epsDirPath(dir, task.albumId, task.epsId));
      if (!epsDir.existsSync()) epsDir.createSync(recursive: true);
      final aid = int.tryParse(task.albumId) ?? 0;
      final needScramble = Scramble.needScramble(aid, task.scrambleId);

      // 任务内图片并行下载：多个 worker 抢占下一个未完成页码，
      // 文件按页码命名，写入顺序无需保证。
      var next = task.completed;
      var failedMsg = '';

      Future<void> worker() async {
        while (task.status != DownloadStatus.paused) {
          final i = next++;
          if (i >= task.imageUrls.length) return;
          final url = task.imageUrls[i];
          try {
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
          } catch (e) {
            // 单张失败：记录原因继续其余图片，最后标记任务可重试
            failedMsg = e.toString();
          }
        }
      }

      final n = imageConcurrency.clamp(1, 8);
      await Future.wait(
        List<Future<void>>.generate(n, (_) => worker()),
      );
      if (task.status == DownloadStatus.paused) return;

      if (task.completed < task.imageUrls.length) {
        // 存在未完成图片：标记失败并保留进度，可点击"继续"重试
        task.setStatus(
          DownloadStatus.error,
          failedMsg.isEmpty ? '部分图片下载失败，可点击"继续"重试' : failedMsg,
        );
        notifyListeners();
        return;
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
