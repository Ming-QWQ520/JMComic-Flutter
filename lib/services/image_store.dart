import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/protocol/jm_client.dart';

/// 统一图片存储（封面 / 头像等 Flutter 侧小图加载）。
///
/// 背景（修复"日志反复出现图片解码失败"）：
/// - 旧实现用 CachedNetworkImage / NetworkImage 直接加载封面与头像。
///   当 CDN 被 WAF 拦截返回 200 + HTML 反爬页、或 `_3x4` 封面变体
///   不存在返回错误页时，坏字节会一路交给图片解码器，反复输出
///   Failed to decode image 日志，且坏数据会进磁盘缓存反复触发。
/// - 头像此前甚至没有携带自定义 UA，Dart 默认 UA 更易被拦截。
///
/// 现在：所有小图统一走 [JmClient.fetchImage]（自带 UA 头、魔数校验、
/// 图片域名轮询与 `_3x4` 回退），校验通过的字节才落盘/进内存缓存，
/// 从根上消除"把反爬网页交给解码器"的日志噪音。
class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  /// 内存缓存上限（条目数）。封面/头像均为小图，200 张 ≈ 10~20MB。
  static const int _memLimit = 200;

  /// 磁盘缓存上限（字节，80MB）：超出后按文件修改时间从旧到新清理。
  /// 长时间使用封面/头像缓存会持续增长，此上限控制磁盘占用。
  static const int _diskLimit = 80 * 1024 * 1024;

  bool _trimmed = false;

  final Map<String, Uint8List> _mem = <String, Uint8List>{};
  final List<String> _memOrder = <String>[];
  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};
  Directory? _dir;

  /// 缓存键：使用 URL 的 path 部分（不随图片线路 host 切换失效）。
  static String _key(String url) {
    final u = Uri.tryParse(url);
    final p = (u != null && u.path.isNotEmpty) ? u.path : url;
    return md5.convert(utf8.encode(p)).toString();
  }

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/jm_img');
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
    // 冷启动后异步清理一次超限的磁盘缓存（不阻塞加载）。
    if (!_trimmed) {
      _trimmed = true;
      scheduleMicrotask(_trimDisk);
    }
    return d;
  }

  /// 磁盘缓存超限时按修改时间从旧到新删除，直到回到上限的 70%。
  Future<void> _trimDisk() async {
    try {
      final d = await _cacheDir();
      final files = d
          .listSync()
          .whereType<File>()
          .map((f) => (f, f.lastModifiedSync().millisecondsSinceEpoch))
          .toList();
      var total = 0;
      for (final (f, _) in files) {
        total += f.lengthSync();
      }
      if (total <= _diskLimit) return;
      files.sort((a, b) => a.$2.compareTo(b.$2)); // 旧的在前
      final target = (_diskLimit * 0.7).toInt();
      for (final (f, _) in files) {
        if (total <= target) break;
        final len = f.lengthSync();
        try {
          f.deleteSync();
          total -= len;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 加载图片字节；失败返回 null（调用方渲染占位/错误组件）。
  ///
  /// 相同 URL 的并发请求会被合并为一次真实下载。
  Future<Uint8List?> load(String url) {
    if (url.isEmpty) return Future<Uint8List?>.value(null);
    final hit = _mem[url];
    if (hit != null) {
      _touch(url);
      return Future<Uint8List?>.value(hit);
    }
    final going = _inflight[url];
    if (going != null) return going;
    final f = _load(url);
    _inflight[url] = f;
    return f.whenComplete(() => _inflight.remove(url));
  }

  Future<Uint8List?> _load(String url) async {
    // 1. 磁盘缓存（读出后仍做魔数校验，防止历史坏数据反复报解码错误）
    try {
      final d = await _cacheDir();
      final f = File('${d.path}/${_key(url)}');
      if (f.existsSync()) {
        final bytes = await f.readAsBytes();
        if (bytes.length > 12 && JmClient.looksLikeImage(bytes)) {
          _putMem(url, bytes);
          return bytes;
        }
        f.deleteSync(); // 坏缓存清理
      }
    } catch (_) {}

    // 2. 远程下载（fetchImage 已含 UA 头 / 魔数校验 / _3x4 回退 / 换线路）
    Uint8List? bytes;
    try {
      final raw = await JmClient.instance.fetchImage(url);
      bytes = Uint8List.fromList(raw);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) return null;

    _putMem(url, bytes);
    // 3. 写磁盘缓存（失败不影响本次加载）
    try {
      final d = await _cacheDir();
      await File('${d.path}/${_key(url)}').writeAsBytes(bytes, flush: true);
    } catch (_) {}
    return bytes;
  }

  void _putMem(String url, Uint8List bytes) {
    if (_mem[url] == null) _memOrder.add(url);
    _mem[url] = bytes;
    _touch(url);
    while (_memOrder.length > _memLimit) {
      final evict = _memOrder.removeAt(0);
      _mem.remove(evict);
    }
  }

  void _touch(String url) {
    _memOrder.remove(url);
    _memOrder.add(url);
  }

  /// 清理全部缓存（设置页"清理图片缓存"入口）。
  Future<void> clear() async {
    _mem.clear();
    _memOrder.clear();
    try {
      final d = await _cacheDir();
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// 当前磁盘缓存大小（字节），设置页展示用。
  Future<int> diskUsage() async {
    try {
      final d = await _cacheDir();
      if (!d.existsSync()) return 0;
      var total = 0;
      await for (final e in d.list()) {
        if (e is File) total += e.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

/// 基于 [ImageStore] 的通用远程图片组件。
///
/// 加载中展示占位，失败展示 [error] 构建结果；字节在进入解码器前
/// 已经过魔数校验，不会再出现反爬页导致的解码失败日志。
class StoreImage extends StatefulWidget {
  const StoreImage({
    super.key,
    required this.url,
    this.fit,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.placeholder,
    this.error,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? error;

  @override
  State<StoreImage> createState() => _StoreImageState();
}

class _StoreImageState extends State<StoreImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = ImageStore.instance.load(widget.url);
  }

  @override
  void didUpdateWidget(StoreImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = ImageStore.instance.load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.placeholder?.call(context) ??
              Container(
                width: widget.width,
                height: widget.height,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              );
        }
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return widget.error?.call(context) ??
              Container(
                width: widget.width,
                height: widget.height,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Theme.of(context).colorScheme.outline,
                ),
              );
        }
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          gaplessPlayback: true,
        );
      },
    );
  }
}
