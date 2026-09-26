import 'package:flutter/material.dart';

import '../constants.dart';

/// 应用主题（对齐 JMComic-qt 的 6 套 QSS 主题配色）。
class AppTheme {
  AppTheme._();

  /// 按方案构建浅色/深色主题。
  ///
  /// [transparent] = 自定义背景图模式下，Scaffold / AppBar / 底栏
  /// 背景透明化，让全局背景图层透出（阅读器自行指定黑色背景不受影响）。
  /// [cardOpacity] = 前景 UI 元素（Card / 底栏 / ListTile）背景色的
  /// 透明度，0~1。1=完全不透明，<1 时 surface 色按比例变透，使全局
  /// 自定义背景从前景卡片缝隙透出，对应设置页「选项透明度」。
  static ThemeData light(
          [ThemeScheme scheme = ThemeScheme.lightOrange,
          bool transparent = false,
          double cardOpacity = 1.0]) =>
      _build(scheme, Brightness.light, transparent, cardOpacity);

  /// 按方案构建深色主题。
  static ThemeData dark(
          [ThemeScheme scheme = ThemeScheme.darkOrange,
          bool transparent = false,
          double cardOpacity = 1.0]) =>
      _build(scheme, Brightness.dark, transparent, cardOpacity);

  /// 按方案 + 亮度构建（方案亮度与请求亮度不一致时以方案亮度为主）。
  static ThemeData of(ThemeScheme scheme) =>
      _build(scheme, scheme.isDark ? Brightness.dark : Brightness.light);

  static ThemeData _build(
    ThemeScheme scheme,
    Brightness brightness, [
    bool transparent = false,
    double cardOpacity = 1.0,
  ]) {
    final c = SchemeColors.of(scheme);
    final isDark = c.isDark;
    // 选项透明度：用户在「设置 → 个性化 → 选项透明度」中调节，0~1。
    // 直接作用于 surface 色的 alpha，影响 Card / NavigationBar / ListTile
    // 等以 surface 为背景的前景组件；text/icon 颜色不受影响。
    final co = cardOpacity.clamp(0.0, 1.0);
    final surface = co >= 1.0 ? c.surface : c.surface.withValues(alpha: co);
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: c.primary,
      secondary: c.primary,
      surface: surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: transparent ? Colors.transparent : c.bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: transparent ? Colors.transparent : c.bg,
        foregroundColor: isDark ? Colors.white : const Color(0xFF555555),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF555555),
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        // 关键修复：原来写 c.surface 绕过了上面的 cardOpacity 处理，
        // 导致「选项透明度」滑杆调节完全无可见变化。改为用已 alpha
        // 处理过的 surface 变量，Card 背景才会随滑杆变透。
        color: surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dims.radiusM),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        // 同上：用 surface（已应用 cardOpacity alpha）而非 c.surface。
        backgroundColor: transparent ? Colors.transparent : surface,
        indicatorColor: c.primary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? c.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dims.radiusS),
        ),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dims.radiusM),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // 同上：输入框填充色也走 surface，让选项透明度生效。
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dims.radiusM),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dims.radiusM),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dims.radiusM),
          borderSide: BorderSide(color: c.primary, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 0.6,
        space: 0.6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dims.radiusS),
        ),
      ),
    );
  }
}
