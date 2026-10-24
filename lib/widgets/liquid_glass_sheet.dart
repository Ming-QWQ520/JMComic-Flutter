import 'dart:ui';

import 'package:flutter/material.dart';

/// 液态玻璃（Liquid Glass / Glassmorphism）弹出选择框。
///
/// 替代系统 PopupMenuButton 的自定义弹出框（用户需求：排序按键样式
/// 需要精美现代化，透明 + 轻微液态玻璃效果）。构成：
/// - Dialog 半透明遮罩（轻微压暗背景）；
/// - BackdropFilter 高斯模糊（sigma 22）磨砂底层；
/// - 半透明渐变面板 + 顶部高光描边 + 柔和投影，营造"液态玻璃"质感；
/// - 明暗主题自适应；多分组（如 排序 + 搜索类型）单弹窗内联展示，
///   点击任一选项立即生效并返回 (sectionId, value)。
class LiquidGlassPicker {
  LiquidGlassPicker._();

  /// 弹出玻璃选择框。
  ///
  /// [sections] 为分组列表；返回被点击选项所在的分组 id 与其值，
  /// 点击遮罩/取消返回 null。
  static Future<({String sectionId, Object value})?> show(
    BuildContext context, {
    required String title,
    IconData titleIcon = Icons.tune_rounded,
    required List<GlassSection<Object>> sections,
  }) {
    return showDialog<(String, Object)>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (BuildContext ctx) => _GlassDialog(
        title: title,
        titleIcon: titleIcon,
        sections: sections,
      ),
    ).then(((String, Object)? r) =>
        r == null ? null : (sectionId: r.$1, value: r.$2));
  }
}

/// 一个玻璃选择框内的单条选项。
class GlassOption<T extends Object> {
  const GlassOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 弹出框内的一个分组（标题 + 选项列表 + 当前选中值）。
class GlassSection<T extends Object> {
  const GlassSection({
    required this.id,
    required this.title,
    required this.options,
    required this.selected,
  });

  final String id;
  final String title;
  final List<GlassOption<T>> options;
  final T selected;
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.title,
    required this.titleIcon,
    required this.sections,
  });

  final String title;
  final IconData titleIcon;
  final List<GlassSection<Object>> sections;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final cs = Theme.of(context).colorScheme;
    final bool dark = brightness == Brightness.dark;

    // —— 液态玻璃配色（明/暗两套）——
    final Color glassTop = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.72);
    final Color glassBottom = dark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.46);
    final Color borderColor = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);
    final Color titleColor = dark ? Colors.white : const Color(0xFF2A2E33);
    final Color subColor = dark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.42);

    final double maxH = MediaQuery.of(context).size.height * 0.68;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[glassTop, glassBottom],
                stops: const <double>[0, 1],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
                // 顶部内侧高光：玻璃上缘的反光感
                BoxShadow(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.65),
                  blurRadius: 1,
                  offset: const Offset(0, -0.6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // —— 标题行 ——
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(titleIcon, size: 17, color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        _GlassCloseButton(dark: dark),
                      ],
                    ),
                  ),
                  // —— 分组 ——
                  for (int gi = 0; gi < sections.length; gi++) ...<Widget>[
                    if (gi > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Divider(
                          height: 14,
                          thickness: 0.6,
                          color: (dark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 14, 6),
                      child: Text(
                        sections[gi].title,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: subColor,
                        ),
                      ),
                    ),
                    for (final GlassOption<Object> opt in sections[gi].options)
                      _GlassOptionRow(
                        label: opt.label,
                        icon: opt.icon,
                        selected: opt.value == sections[gi].selected,
                        dark: dark,
                        onTap: () =>
                            Navigator.pop<(String, Object)>(
                                context, (sections[gi].id, opt.value)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个选项行（选中态带主题色填充 + 对勾）。
class _GlassOptionRow extends StatelessWidget {
  const _GlassOptionRow({
    required this.label,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: dark ? 0.22 : 0.13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon,
                      size: 18,
                      color: selected
                          ? cs.primary
                          : (dark ? Colors.white70 : Colors.black45)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? cs.primary
                          : (dark ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF3A3F45)),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      ScaleTransition(scale: a, child: child),
                  child: selected
                      ? Icon(Icons.check_rounded,
                          key: const ValueKey<bool>(true),
                          size: 18,
                          color: cs.primary)
                      : const SizedBox(width: 18, key: ValueKey<bool>(false)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃质感关闭按钮。
class _GlassCloseButton extends StatelessWidget {
  const _GlassCloseButton({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(100),
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
          border: Border.all(
            color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 15,
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.65),
        ),
      ),
    );
  }
}
