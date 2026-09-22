import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 通知中心：列表 + 加载更多 + 标记已读。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final JmApi _api = JmApi.instance;
  List<dynamic> _items = <dynamic>[];
  bool _loading = true;
  String _error = '';
  int _page = 1;
  bool _noMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = '';
        _page = 1;
        _noMore = false;
      });
    }
    try {
      final data = await _api.getNotifications(page: _page);
      List list = const [];
      if (data is List) {
        list = data;
      } else if (data is Map) {
        list = (data['list'] ?? data['data'] ?? data['notifications'] ?? [])
            as List;
      }
      if (!mounted) return;
      setState(() {
        if (reset) _items = list;
        if (list.isEmpty) {
          _noMore = true;
        } else {
          _items.addAll(list);
          _page++;
        }
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

  Future<void> _markAllRead() async {
    try {
      await _api.postNotifications(<String, dynamic>{'type': 'all'});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已全部标记为已读')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知中心'),
        actions: <Widget>[
          IconButton(
            tooltip: '全部已读',
            icon: const Icon(Icons.done_all_rounded),
            onPressed: _markAllRead,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: () => _load())
              : _items.isEmpty
                  ? const EmptyView(message: '暂无通知', icon: Icons.notifications_none_rounded)
                  : RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length + (_noMore ? 0 : 1),
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext c, int i) {
                          if (i >= _items.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: TextButton(
                                onPressed: () => _load(reset: false),
                                child: const Text('加载更多'),
                              ),
                            );
                          }
                          final item = _items[i];
                          if (item is! Map) {
                            return Card(
                              child: ListTile(title: Text(item.toString())),
                            );
                          }
                          return Card(
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.circle_notifications_rounded,
                                  size: 20,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                (item['title'] ?? item['content'] ?? '(无标题)')
                                    .toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              subtitle: Text(
                                (item['content'] ?? item['msg'] ?? '')
                                    .toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// 任务与签到页：每日签到 / 任务列表 / J币信息。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final JmApi _api = JmApi.instance;
  dynamic _daily;
  dynamic _tasks;
  bool _loading = true;
  String _error = '';
  bool _checkingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = context.read<AppState>();
    final uid = state.user?.id ?? '';
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        if (uid.isNotEmpty)
          _api.getDaily(uid)
        else
          Future<dynamic>.value(null),
        _api.getTasks(),
      ]);
      if (!mounted) return;
      setState(() {
        _daily = results[0];
        _tasks = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkIn() async {
    setState(() => _checkingIn = true);
    try {
      final r = await _api.dailyCheckIn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('签到结果: ${r ?? "成功"}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('签到失败: $e')));
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('任务与签到')),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    // 签到卡片
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('每日签到',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            state.user != null
                                ? '当前 J币 ${state.user!.coin} · 经验 ${state.user!.exp} · 等级 ${state.user!.level}'
                                : '登录后可签到并领取奖励',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12.5),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: cs.primary,
                            ),
                            onPressed: _checkingIn ? null : _checkIn,
                            icon: _checkingIn
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.edit_calendar_rounded,
                                    size: 18),
                            label: Text(_checkingIn ? '签到中…' : '立即签到'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // J币充值入口
                    Card(
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1C40F)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.monetization_on_rounded,
                              color: Color(0xFFE6A817), size: 20),
                        ),
                        title: const Text('J 币充值',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('coin_buy_charge 接口',
                            style: TextStyle(fontSize: 12)),
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                        onTap: _charge,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_daily != null) ...<Widget>[
                      SectionHeader(title: '每日任务信息'),
                      JsonPreview(data: _daily),
                      const SizedBox(height: 14),
                    ],
                    SectionHeader(title: '任务列表'),
                    JsonPreview(data: _tasks),
                    const SizedBox(height: 12),
                    Center(
                      child: Text('数据来自 daily / tasks 接口',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.outline)),
                    ),
                  ],
                ),
    );
  }

  Future<void> _charge() async {
    try {
      final r = await _api.coinBuyCharge();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('充值信息'),
          content:
              SingleChildScrollView(child: Text(r?.toString() ?? '无')),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }
}

/// 简单 JSON 预览卡片。
class JsonPreview extends StatelessWidget {
  const JsonPreview({super.key, this.data});

  final dynamic data;

  @override
  Widget build(BuildContext context) {
    var text = data?.toString() ?? '无数据';
    if (text.length > 1200) text = text.substring(0, 1200);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
