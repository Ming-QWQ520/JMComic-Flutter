/// JMComic-Flutter 设计常量（主题色对齐 tonquer/JMComic-qt QSS 主题）。
library;

import 'package:flutter/material.dart';

/// 当前应用版本（与 pubspec.yaml `version:` 保持一致；GitHub Release
/// 中的 APK 命名同样使用该版本号，检测更新据此比对。core_test.dart
/// 有同步性测试防止两者漂移）。
const String kAppVersion = '0.1.2';

/// 主题配色方案（需求变更：去除橙色系，仅保留深/浅两套青色配色）。
///
/// 历史说明：v0.1.1 及之前为 深浅·橙 / 深浅·青 四套；v0.1.2 起移除
/// 橙色系与粉色系，旧用户持久化的 legacy key 会在 fromKey 中自动
/// 回落到对应明暗的青色方案。默认主题改为「跟随系统」。
enum ThemeScheme {
  lightTeal('light_teal', '浅色·青'),
  darkTeal('dark_teal', '深色·青');

  const ThemeScheme(this.key, this.label);

  /// 持久化 key。
  final String key;

  /// 中文显示名。
  final String label;

  bool get isDark => key.startsWith('dark');

  /// 解析持久化 key；旧版橙色/粉色 key 自动映射到同明暗的青色方案
  /// （去除橙色系后老用户无感迁移）。
  static ThemeScheme fromKey(String key) {
    switch (key) {
      case 'dark_orange':
      case 'dark_pink':
        return ThemeScheme.darkTeal;
      case 'light_orange':
      case 'light_pink':
      case 'light_teal':
        return ThemeScheme.lightTeal;
      case 'dark_teal':
        return ThemeScheme.darkTeal;
      default:
        return ThemeScheme.lightTeal;
    }
  }
}

/// 主题色板（青色双方案：明/暗）。
class SchemeColors {
  const SchemeColors({
    required this.primary,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.isDark,
  });

  /// 浅色·青 light_teal。
  static const SchemeColors lightTeal = SchemeColors(
    primary: Color(0xFF1DE9B6),
    accent: Color(0xFF6EFFE8),
    bg: Color(0xFFE6E6E6),
    surface: Colors.white,
    isDark: false,
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
        ThemeScheme.lightTeal => lightTeal,
        ThemeScheme.darkTeal => darkTeal,
      };

  final Color primary;
  final Color accent;
  final Color bg;
  final Color surface;
  final bool isDark;
}

/// 兼容旧引用的品牌色（现统一为青色系）。
class Brand {
  Brand._();

  static const Color primary = Color(0xFF1DE9B6);
  static const Color accent = Color(0xFF6EFFE8);
  static const Color success = Color(0xFF17A2B8);
  static const Color danger = Color(0xFFDC3545);
  static const Color warning = Color(0xFFFFC107);
  static const Color darkBg = Color(0xFF31363B);
  static const Color darkSurface = Color(0xFF3B4148);
  static const Color lightBg = Color(0xFFE6E6E6);
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

/// 动画开关集合（设置 > 动画设置）。
///
/// 需求：新增四类可独立开关的动效，默认只开启「页面转场」与「Hero 转场」：
/// - [pageTransitions] 页面转场动画（滑动/淡入转场；关闭后瞬时切换）；
/// - [heroEnabled] Hero 封面联动转场（列表封面 → 详情页头图）；
/// - [physicsAnimations] 物理仿真动画（弹簧回弹/阻尼滚动物理）；
/// - [card3d] 3D 卡片动画（封面卡片随触摸位置的透视倾斜）。
class AnimationOptions {
  AnimationOptions({
    bool? pageTransitions,
    bool? hero,
    bool? physics,
    bool? card3d,
  })  : pageTransitions = pageTransitions ?? true,
        heroEnabled = hero ?? true,
        physicsAnimations = physics ?? false,
        card3d = card3d ?? false;

  bool pageTransitions;
  bool heroEnabled;
  bool physicsAnimations;
  bool card3d;

  /// 从持久化键值快照恢复（缺省回落默认值）。
  factory AnimationOptions.fromMap(Map<String, Object> m) => AnimationOptions(
        pageTransitions: (m['anim_page_transitions'] as bool?) ?? true,
        hero: (m['anim_hero'] as bool?) ?? true,
        physics: (m['anim_physics'] as bool?) ?? false,
        card3d: (m['anim_card3d'] as bool?) ?? false,
      );
}
