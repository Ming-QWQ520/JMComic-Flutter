/// 数字展示格式化工具。
///
/// 对齐 JM 官方 App 的 K/M 缩写习惯：
/// `944 → 944`、`11600 → 1.2万`？——不，按需求直接 K/M：
/// `11600 → 11.6K`、`66800 → 66.8K`、`1234567 → 1.2M`。
library;

/// 将计数格式化为 K / M 缩写（浏览数、喜欢数等）。
///
/// - < 1000：原样返回；
/// - < 1,000,000：`x.xK`（不足 1K 的百位聚合为 0.1K 粒度，如 999 → 999）；
/// - ≥ 1,000,000：`x.xM`。
///
/// 小数位仅在有值时保留（`11.0K → 11K`）。
String formatCount(dynamic value) {
  final n = value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  if (n < 0) return '0';
  if (n < 1000) return '$n';
  double v;
  String unit;
  if (n < 1000000) {
    v = n / 1000;
    unit = 'K';
  } else if (n < 1000000000) {
    v = n / 1000000;
    unit = 'M';
  } else {
    v = n / 1000000000;
    unit = 'B';
  }
  // 保留一位小数；整值去掉 ".0"。
  var s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '$s$unit';
}
