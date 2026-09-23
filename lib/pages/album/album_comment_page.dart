import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/feedback.dart';

/// 评论页（对齐 qt CommentView / SubCommentView）。
///
/// 功能：评论分页加载、子评论展开、发送评论与回复、我的评论管理入口。
class AlbumCommentPage extends StatefulWidget {
  const AlbumCommentPage({
    super.key,
    required this.albumId,
    this.albumName = '',
  });

  final String albumId;
  final String albumName;

  @override
  State<AlbumCommentPage> createState() => _AlbumCommentPageState();
}

class _AlbumCommentPageState extends State<AlbumCommentPage> {
  final JmApi _api = JmApi.instance;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  final List<CommentInfo> _comments = <CommentInfo>[];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  String _error = '';

  /// 当前回复的评论（null 则发送顶层评论）。
  CommentInfo? _replyTo;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await _api.getComments(widget.albumId, page: 1);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(data.list);
        _total = data.total;
        _page = 1;
        _noMore = _comments.length >= data.total;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _loading) return;
    _loadingMore = true;
    try {
      final data = await _api.getComments(widget.albumId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _comments.addAll(data.list);
        _noMore = _comments.length >= _total;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录后再评论')));
      Navigator.pushNamed(context, '/login');
      return;
    }
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    try {
      await _api.sendComment(widget.albumId, text, cid: reply?.id ?? '');
      if (!mounted) return;
      _input.clear();
      setState(() => _replyTo = null);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('评论已发送，等待审核通过后显示')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('评论 ($_total)'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error.isNotEmpty
                    ? ErrorView(message: _error, onRetry: _load)
                    : _comments.isEmpty
                        ? const EmptyView(message: '暂无评论，快来抢沙发')
                        : ListView.separated(
                            controller: _scroll,
                            padding: const EdgeInsets.all(14),
                            itemCount: _comments.length + (_noMore ? 0 : 1),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i >= _comments.length) {
                                return const TailLoader();
                              }
                              return _CommentCard(
                                comment: _comments[i],
                                api: _api,
                                onReply: () =>
                                    setState(() => _replyTo = _comments[i]),
                              );
                            },
                          ),
          ),
          // 底部输入栏
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyTo != null)
                          Row(
                            children: [
                              Text(
                                '回复 ${_replyTo!.username}',
                                style: tt.labelSmall
                                    ?.copyWith(color: cs.primary),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () =>
                                    setState(() => _replyTo = null),
                              ),
                            ],
                          ),
                        TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: '发表评论…',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 评论卡片（含子评论展开）。
class _CommentCard extends StatefulWidget {
  const _CommentCard({
    required this.comment,
    required this.api,
    required this.onReply,
  });

  final CommentInfo comment;
  final JmApi api;
  final VoidCallback onReply;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = widget.comment;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  backgroundImage: c.headPath.isEmpty
                      ? null
                      : NetworkImage(widget.api.avatarUrl(c.headPath)),
                  child: c.headPath.isEmpty
                      ? Icon(Icons.person_rounded,
                          size: 18, color: cs.primary)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(c.username,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        '${c.levelName} · ${_formatTime(c.addTime)}',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(c.content, style: tt.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(Icons.favorite_border_rounded,
                    size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${c.likes}',
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 18),
                InkWell(
                  onTap: widget.onReply,
                  child: Row(
                    children: [
                      Icon(Icons.reply_rounded,
                          size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('回复',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Spacer(),
                if (c.subList.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Text(
                          '${_expanded ? '收起' : '展开'} ${c.subList.length} 条回复',
                          style: tt.labelSmall?.copyWith(color: cs.primary),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Column(
                  children: c.subList
                      .map((CommentInfo sub) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      cs.primary.withValues(alpha: 0.1),
                                  backgroundImage: sub.headPath.isEmpty
                                      ? null
                                      : NetworkImage(
                                          widget.api.avatarUrl(sub.headPath)),
                                  child: sub.headPath.isEmpty
                                      ? Icon(Icons.person_rounded,
                                          size: 14, color: cs.primary)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        '${sub.username} · ${_formatTime(sub.addTime)}',
                                        style: tt.labelSmall?.copyWith(
                                            color: cs.onSurfaceVariant),
                                      ),
                                      Text(sub.content,
                                          style: tt.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String ts) {
    final t = int.tryParse(ts);
    if (t == null || t <= 0) return ts;
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
