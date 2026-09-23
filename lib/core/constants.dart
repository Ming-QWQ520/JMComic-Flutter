/// JMComic-Flutter 设计常量（主题色对齐 tonquer/JMComic-qt QSS 主题）。
library;

import 'package:flutter/material.dart';

/// 主题配色方案（对齐 JMComic-qt res/theme/*.qss）。
enum ThemeScheme {
  lightOrange('light_orange', '浅色·橙'),
  lightPink('light_pink', '浅色·粉'),
  lightTeal('light_teal', '浅色·青'),
  darkOrange('dark_orange', '深色·橙'),
  darkPink('dark_pink', '深色·粉'),
  darkTeal('dark_teal', '深色·青');

  const ThemeScheme(this.key, this.label);

  /// 持久化 key（对齐 qt 主题文件名）。
  final String key;

  /// 中文显示名。
  final String label;

  bool get isDark => key.startsWith('dark');

  static ThemeScheme fromKey(String key) => ThemeScheme.values.firstWhere(
        (e) => e.key == key,
        orElse: () => ThemeScheme.lightOrange,
      );
}

/// 主题色板（对齐 qt QSS 配色）。
class SchemeColors {
  const SchemeColors({
    required this.primary,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.isDark,
  });

  /// 浅色·橙 light_orange。
  static const SchemeColors lightOrange = SchemeColors(
    primary: Color(0xFFFF7B00),
    accent: Color(0xFFFFA94D),
    bg: Color(0xFFF3F3F3),
    surface: Colors.white,
    isDark: false,
  );

  /// 浅色·粉 light_pink。
  static const SchemeColors lightPink = SchemeColors(
    primary: Color(0xFFFF4081),
    accent: Color(0xFFFF79B0),
    bg: Color(0xFFF3F3F3),
    surface: Colors.white,
    isDark: false,
  );

  /// 浅色·青 light_teal。
  static const SchemeColors lightTeal = SchemeColors(
    primary: Color(0xFF1DE9B6),
    accent: Color(0xFF6EFFE8),
    bg: Color(0xFFE6E6E6),
    surface: Colors.white,
    isDark: false,
  );

  /// 深色·橙 dark_orange。
  static const SchemeColors darkOrange = SchemeColors(
    primary: Color(0xFFFF7B00),
    accent: Color(0xFFFFA94D),
    bg: Color(0xFF31363B),
    surface: Color(0xFF3B4148),
    isDark: true,
  );

  /// 深色·粉 dark_pink。
  static const SchemeColors darkPink = SchemeColors(
    primary: Color(0xFFFF4081),
    accent: Color(0xFFFF79B0),
    bg: Color(0xFF31363B),
    surface: Color(0xFF3B4148),
    isDark: true,
  );

  /// 深色·青 dark_teal。
  static const SchemeColors darkTeal = SchemeColors(
    primary: Color(0xFF1DE9B6),
    accent: Color(0xFF6EFFE8),
    bg: Color(0xFF31363B),
    surface: Color(0xFF3B4148),
    isDark: true,
  );

  static SchemeColors of(ThemeScheme s) => switch (s) {
        ThemeScheme.lightOrange => lightOrange,
        ThemeScheme.lightPink => lightPink,
        ThemeScheme.lightTeal => lightTeal,
        ThemeScheme.darkOrange => darkOrange,
        ThemeScheme.darkPink => darkPink,
        ThemeScheme.darkTeal => darkTeal,
      };

  final Color primary;
  final Color accent;
  final Color bg;
  final Color surface;
  final bool isDark;
}

/// 兼容旧引用的品牌色（默认浅橙方案）。
class Brand {
  Brand._();

  static const Color primary = Color(0xFFFF7B00);
  static const Color accent = Color(0xFFFFA94D);
  static const Color success = Color(0xFF17A2B8);
  static const Color danger = Color(0xFFDC3545);
  static const Color warning = Color(0xFFFFC107);
  static const Color darkBg = Color(0xFF31363B);
  static const Color darkSurface = Color(0xFF3B4148);
  static const Color lightBg = Color(0xFFF3F3F3);
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
