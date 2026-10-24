import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 任务奖励页（对齐官方 2.1.12 API_TASKS_LIST：GET tasks?type=）。
///
/// 展示每日/每周/每月任务与奖励，支持领取（POST tasks 领取奖励）。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final JmApi _api = JmApi.instance;

  static const Map<String, String> _types = <String, String>{
    'daily': '每日',
    'week': '每周',
    'month': '每月',
    'newbie': '新手',
  };

  String _type = 'daily';
  bool _loading = true;
  String _error = '';
  List<dynamic> _tasks = <dynamic>[];
  final Set<String> _claiming = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请先登录后查看任务';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getTasks(_type);
      if (!mounted) return;
      final list = _extractList(data);
      setState(() {
        _tasks = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  static List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const <String>['list', 'data', 'tasks', 'list_data']) {
        final v = data[key];
        if (v is List) return v;
      }
    }
    return <dynamic>[];
  }

  Future<void> _claim(Map task) async {
    final app = context.read<AppState>();
    final taskId = '${task['task_id'] ?? task['id'] ?? ''}';
    if (taskId.isEmpty || taskId == 'null') return;
    setState(() => _claiming.add(taskId));
    try {
      await _api.changeTasks(_type, app.user?.id ?? '', taskId: taskId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('领取成功')));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('领取失败: $e')));
    } finally {
      if (mounted) setState(() => _claiming.remove(taskId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务奖励'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _types.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _type == e.key,
                        onSelected: (_) {
                          _type = e.key;
                          _reload();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
          ? ErrorView(message: _error, onRetry: _reload)
          : RefreshIndicator(
              onRefresh: _reload,
              child: _tasks.isEmpty
                  ? ListView(
                      children: <Widget>[
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              '当前分类暂无任务',
                              style: tt.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _tasks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext c, int i) {
                        final m = _tasks[i];
                        if (m is! Map) return const SizedBox.shrink();
                        final title =
                            '${m['title'] ?? m['task_name'] ?? m['name'] ?? '任务'}';
                        final desc =
                            '${m['content'] ?? m['description'] ?? m['desc'] ?? ''}';
                        final reward =
                            '${m['coin'] ?? m['reward'] ?? m['jcoin'] ?? ''}';
                        final taskId = '${m['task_id'] ?? m['id'] ?? ''}';
                        final status = '${m['status'] ?? m['state'] ?? ''}';
                        final done = status == '2' || status == 'finished';
                        final canClaim =
                            status == '1' && !_claiming.contains(taskId);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary.withValues(alpha: 0.12),
                            child: Icon(
                              Icons.emoji_events_rounded,
                              size: 20,
                              color: cs.primary,
                            ),
                          ),
                          title: Text(title, style: tt.bodyMedium),
                          subtitle: desc.isEmpty
                              ? null
                              : Text(
                                  desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                          trailing: done
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                )
                              : canClaim
                              ? FilledButton.tonal(
                                  onPressed: () => _claim(m),
                                  child: const Text('领取'),
                                )
                              : (_claiming.contains(taskId)
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : reward.isNotEmpty && reward != 'null'
                                    ? Text(
                                        'J币 $reward',
                                        style: tt.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      )
                                    : null),
                        );
                      },
                    ),
            ),
    );
  }
}
