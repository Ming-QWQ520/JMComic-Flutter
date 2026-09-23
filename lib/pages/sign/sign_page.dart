import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 签到页（对齐 qt SignView / OpenSign）。
///
/// - GET daily?user_id= 拉取 {daily_id, record: [[{date, signed}]]}；
/// - 日历展示当月签到状态（已签/未签）；
/// - POST daily_chk {user_id, daily_id} 完成签到。
class SignPage extends StatefulWidget {
  const SignPage({super.key});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  final JmApi _api = JmApi.instance;

  int _dailyId = 0;

  /// day(1-31) → 是否已签。
  final Map<int, bool> _signMap = <int, bool>{};

  bool _loading = true;
  bool _signing = false;
  String _error = '';

  bool get _todaySigned {
    final today = DateTime.now().day;
    return _signMap[today] == true;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请先登录后再签到';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getDaily(app.user!.id);
      if (!mounted) return;
      final map = <int, bool>{};
      var dailyId = 0;
      if (data is Map) {
        dailyId = int.tryParse('${data['daily_id'] ?? 0}') ?? 0;
        final record = data['record'];
        if (record is List) {
          for (final v in record) {
            if (v is! List) continue;
            for (final v2 in v) {
              if (v2 is! Map) continue;
              final date = int.tryParse('${v2['date'] ?? 0}') ?? 0;
              if (date > 0) map[date] = v2['signed'] == true;
            }
          }
        }
      }
      setState(() {
        _dailyId = dailyId;
        _signMap
          ..clear()
          ..addAll(map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _sign() async {
    if (_signing || _dailyId == 0) return;
    final app = context.read<AppState>();
    setState(() => _signing = true);
    try {
      await _api.signDaily(app.user!.id, '$_dailyId');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('签到成功')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('签到失败: $e')));
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final firstWeekday = DateTime(now.year, now.month, 1).weekday % 7;

    return Scaffold(
      appBar: AppBar(title: const Text('每日签到')),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    // 签到状态卡
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: <Widget>[
                            Icon(
                              _todaySigned
                                  ? Icons.verified_rounded
                                  : Icons.event_available_rounded,
                              size: 44,
                              color: cs.primary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _todaySigned ? '今日已签到' : '今日尚未签到',
                              style: tt.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed:
                                  _todaySigned || _signing ? null : _sign,
                              icon: _signing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.touch_app_rounded,
                                      size: 18),
                              label: Text(_todaySigned ? '已签到' : '立即签到'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 当月日历（对齐 qt SignView 31 格）
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${now.year} 年 ${now.month} 月',
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: const <String>[
                                '日', '一', '二', '三', '四', '五', '六',
                              ]
                                  .map((String w) => Expanded(
                                        child: Center(
                                          child: Text(w,
                                              style: tt.labelSmall?.copyWith(
                                                  color: cs.onSurfaceVariant)),
                                        ),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 6),
                            ..._calendarRows(daysInMonth, firstWeekday, cs),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '说明：签到数据来自服务器 daily 接口，绿色为已签到，灰色为未签到或未到日期。',
                      style: tt.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.6),
                    ),
                  ],
                ),
    );
  }

  List<Widget> _calendarRows(int daysInMonth, int firstWeekday, ColorScheme cs) {
    final rows = <Widget>[];
    final totalCells = firstWeekday + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    for (var r = 0; r < rowCount; r++) {
      final cells = <Widget>[];
      for (var w = 0; w < 7; w++) {
        final idx = r * 7 + w - firstWeekday + 1;
        if (idx < 1 || idx > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 34)));
          continue;
        }
        final signed = _signMap[idx] == true;
        final isToday = idx == DateTime.now().day;
        cells.add(
          Expanded(
            child: Container(
              height: 34,
              margin: const EdgeInsets.all(2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: signed
                    ? Colors.green.withValues(alpha: 0.18)
                    : (isToday
                        ? cs.primary.withValues(alpha: 0.1)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
                border: isToday
                    ? Border.all(color: cs.primary, width: 1.2)
                    : null,
              ),
              child: Text(
                '$idx',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                  color: signed ? Colors.green : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }
      rows.add(Row(children: cells));
    }
    return rows;
  }
}
