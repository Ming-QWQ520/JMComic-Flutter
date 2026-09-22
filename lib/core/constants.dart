/// JMComic-Flutter 设计常量。
library;

import 'package:flutter/material.dart';

/// 品牌色板。
class Brand {
  Brand._();

  /// 主色（紫罗兰）。
  static const Color primary = Color(0xFF6C5CE7);

  /// 强调色（品红粉）。
  static const Color accent = Color(0xFFFF6B9D);

  /// 成功 / 在线状态色。
  static const Color success = Color(0xFF00B894);

  /// 深色模式页面背景。
  static const Color darkBg = Color(0xFF0F0F14);

  /// 深色模式卡片背景。
  static const Color darkSurface = Color(0xFF17171F);

  /// 浅色模式页面背景。
  static const Color lightBg = Color(0xFFF7F7FB);
}

/// 通用圆角 / 间距。
class Dims {
  Dims._();

  static const double radiusS = 10;
  static const double radiusM = 16;
  static const double radiusL = 22;
  static const double gapS = 8;
  static const double gapM = 14;
  static const double gapL = 22;
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );
}
