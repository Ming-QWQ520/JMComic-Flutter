import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/jm_api.dart';
import '../state/app_state.dart';

/// 通知中心：列表 + 标记已读。
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
      List list = const <dynamic>[];
      if (data is List) {
        list = data;
      } else if (data is Map) {
        list =
            (data['list'] ?? data['data'] ?? data['notifications'] ?? []) as List;
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_error, textAlign: TextAlign.center),
                      FilledButton.tonal(
                          onPressed: () => _load(), child: const Text('重试')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('暂无通知'))
                  : RefreshIndicator(
                      onRefresh: () async => _load(),
                      child: ListView.builder(
                        itemCount: _items.length + (_noMore ? 0 : 1),
                        itemBuilder: (BuildContext c, int i) {
                          if (i >= _items.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: TextButton(
                                  onPressed: () => _load(reset: false),
                                  child: const Text('加载更多'),
                                ),
                              ),
                            );
                          }
                          final item = _items[i];
                          if (item is! Map) {
                            return ListTile(title: Text(item.toString()));
                          }
                          return ListTile(
                            leading: const Icon(
                                Icons.circle_notifications_rounded),
                            title: Text(
                              (item['title'] ?? item['content'] ?? '(无标题)')
                                  .toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              (item['content'] ?? item['msg'] ?? '').toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('签到结果: ${r ?? "成功"}')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('任务与签到')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(_error, textAlign: TextAlign.center),
                      FilledButton.tonal(
                          onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('每日签到',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            if (state.user != null)
                              Text(
                                '当前 J币: ${state.user!.coin} · 经验: ${state.user!.exp} · 等级: ${state.user!.level}',
                              ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _checkingIn ? null : _checkIn,
                              icon: const Icon(Icons.edit_calendar_rounded),
                              label:
                                  Text(_checkingIn ? '签到中...' : '立即签到'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.monetization_on_rounded),
                        title: const Text('J 币充值'),
                        subtitle: const Text('coin_buy_charge'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          try {
                            final r = await _api.coinBuyCharge();
                            if (!context.mounted) return;
                            showDialog<void>(
                              context: context,
                              builder: (BuildContext c) => AlertDialog(
                                title: const Text('充值信息'),
                                content: SingleChildScrollView(
                                    child: Text(r?.toString() ?? '无')),
                                actions: <Widget>[
                                  TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('关闭')),
                                ],
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('失败: $e')));
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_daily != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('每日任务信息',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          JsonPreview(data: _daily),
                          const SizedBox(height: 12),
                        ],
                      ),
                    Text('任务列表',
                        style: Theme.of(context).textTheme.titleMedium),
                    JsonPreview(data: _tasks),
                  ],
                ),
    );
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
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
