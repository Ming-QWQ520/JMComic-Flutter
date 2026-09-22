import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

/// 章节图片"乱序混淆"还原算法（与 JMcomic-API scramble 包一致）。
///
/// 原理（还原自 APK 源码 canvas 逻辑）：
/// - 是否需要还原：album_id >= scramble_id 且非 .gif；
/// - 切片数量 r：md5_hex(album_id + 文件名) 末字符 ASCII 码，
///   album_id ∈ [268850, 421925] 时 r %= 10；album_id >= 421926 时 r %= 8；
///   再查表 [2,4,6,8,10,12,14,16,18,20]；
/// - 还原：图片按高度垂直等切 num 片（余数并入第 0 片），
///   源图自底部起的第 c 片对应还原图自顶部起的第 c 片。
class Scramble {
  Scramble._();

  static const List<int> _numTable = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20];

  static const int _rangeLow = 268850;
  static const int _rangeHigh = 421925;
  static const int _rangeGte = 421926;

  /// 判断是否需要乱序还原。
  static bool needScramble(int albumId, int scrambleId) =>
      albumId >= scrambleId;

  /// 从图片 URL 提取乱序计算所需的文件名（不含扩展名）。
  /// 例: https://cdn/media/photos/422889/00001.webp?t=1 → "00001"
  static String filenameFromUrl(String imgUrl) {
    var u = imgUrl;
    final qi = u.indexOf('?');
    if (qi >= 0) u = u.substring(0, qi);
    final start = u.lastIndexOf('/') + 1;
    var name = u.substring(start);
    final dot = name.lastIndexOf('.');
    if (dot >= 0) name = name.substring(0, dot);
    return name;
  }

  /// 计算图片乱序切片数。
  static int scrambleNum(String albumId, String filename) {
    final sum = md5.convert(utf8.encode(albumId + filename)).toString();
    var r = sum.codeUnitAt(sum.length - 1);
    final aid = int.tryParse(albumId) ?? 0;
    if (aid >= _rangeLow && aid <= _rangeHigh) {
      r %= 10;
    } else if (aid >= _rangeGte) {
      r %= 8;
    }
    if (r >= 0 && r < _numTable.length) return _numTable[r];
    return 10;
  }

  /// 下载的图片字节 → 还原后的图片字节。
  ///
  /// 内部使用 dart:ui 解码（Flutter 引擎原生支持 WEBP/JPEG/PNG），
  /// 按切片算法在 Canvas 上重新拼接后编码为 PNG。
  static Future<Uint8List> descramble(
      Uint8List data, String albumId, String filename) async {
    final num = scrambleNum(albumId, filename);
    if (num <= 1) return data;

    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    codec.dispose();

    final w = src.width;
    final h = src.height;
    if (h < num) {
      src.dispose();
      return data;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final rem = h % num;
    final base = h ~/ num;

    for (var c = 0; c < num; c++) {
      var sliceH = base;
      final srcY = h - base * (c + 1) - rem;
      var dstY = base * c;
      if (c == 0) {
        sliceH += rem; // 第 0 片（最底部）承担余数
      } else {
        dstY += rem; // 其余片段整体下移余数
      }
      canvas.drawImageRect(
        src,
        ui.Rect.fromLTWH(0, srcY.toDouble(), w.toDouble(), sliceH.toDouble()),
        ui.Rect.fromLTWH(0, dstY.toDouble(), w.toDouble(), sliceH.toDouble()),
        paint,
      );
    }
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    picture.dispose();

    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();

    if (bd == null) return data;
    return bd.buffer.asUint8List();
  }
}
