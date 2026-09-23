import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';

/// 搜索页。
///
/// 支持两种方式：
/// 1. 输入纯数字漫画编号 → 出现「编号直达」卡片，点击直接打开详情页；
/// 2. 输入名称/关键词 → 常规搜索（可切换排序），另提供热门标签与搜索历史。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  AlbumGrid? _grid;
  String _keyword = '';
  String _order = 'mr';

  /// 搜索类型（对齐 qt GetSearchReq2 search_type）。
  String _searchType = '';

  static const Map<String, String> _searchTypes = <String, String>{
    '': '全部',
    'tag': '标签',
    'author': '作者',
    'work': '作品',
    'character': '角色',
    'site': '站内',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 输入是否为纯数字（漫画编号）。
  bool get _isNumericQuery =>
      RegExp(r'^\d{1,12}$').hasMatch(_ctrl.text.trim());

  Future<void> _search([String? kw]) async {
    final k = (kw ?? _ctrl.text).trim();
    if (k.isEmpty) return;
    _focus.unfocus();
    setState(() {
      _keyword = k;
      _ctrl.text = k;
      _grid = null; // 先重建 key，确保强制刷新
    });
    await context.read<AppState>().addSearchHistory(k);
    if (!mounted) return;
    setState(() {
      _grid = AlbumGrid(key: ValueKey<String>('search-$k-$_order'), fetchPage: _fetch);
    });
  }

  Future<List<SearchAlbum>?> _fetch(int page) async {
    try {
      final r = await JmApi.instance.searchComic(_keyword, page,
          order: _order, searchType: _searchType);
      return r.content;
    } catch (_) {
      return null;
    }
  }

  /// 编号直达：先查详情，成功后进入详情页。
  Future<void> _openById(String id) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final album = await JmApi.instance.getAlbum(id);
      // 预热封面字段，详情页用 album.id 展示
      if (album.id == 0) throw StateError('专辑不存在');
      navigator.pushNamed('/album', arguments: album.id.toString());
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('编号 $id 打开失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: _SearchField(
          controller: _ctrl,
          focusNode: _focus,
          onSubmitted: _search,
          onClear: () => setState(() {
            _ctrl.clear();
            _keyword = '';
            _grid = null;
          }),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _search(),
          ),
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.tune_rounded),
            onSelected: (String v) {
              setState(() => _order = v);
              if (_keyword.isNotEmpty) _search(_keyword);
            },
            itemBuilder: (_) => const <PopupMenuItem<String>>[
              PopupMenuItem<String>(value: 'mr', child: Text('最新')),
              PopupMenuItem<String>(value: 'mv', child: Text('最多点击')),
              PopupMenuItem<String>(value: 'mp', child: Text('最多图片')),
              PopupMenuItem<String>(value: 'tf', child: Text('最多爱心')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _grid != null
          ? Column(
              children: [
                if (_isNumericQuery) _buildIdJumpCard(cs, tt),
                Expanded(child: _grid!),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 编号直达入口
                _buildIdJumpCard(cs, tt),
                const SizedBox(height: 20),
                // 搜索历史
                if (state.searchHistory.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeader(title: '搜索历史'),
                      ),
                      IconButton(
                        tooltip: '清空历史',
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 20, color: cs.onSurfaceVariant),
                        onPressed: () =>
                            context.read<AppState>().clearSearchHistory(),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: state.searchHistory
                        .map((String h) => ActionChip(
                              label: Text(h),
                              labelStyle: const TextStyle(fontSize: 12.5),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                _ctrl.text = h;
                                _search(h);
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                // 搜索类型（对齐 qt search_type）
                SectionHeader(title: '搜索类型'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _searchTypes.entries
                      .map((MapEntry<String, String> e) => ChoiceChip(
                            label: Text(e.value),
                            selected: _searchType == e.key,
                            onSelected: (_) {
                              setState(() => _searchType = e.key);
                              if (_keyword.isNotEmpty) _search(_keyword);
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                Text(
                  '小提示：输入纯数字编号可直达漫画详情页；\n支持「作者:名字 / 作品:名字」等搜索语法。',
                  style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant, height: 1.6),
                ),
              ],
            ),
    );
  }

  /// 编号直达卡片。
  Widget _buildIdJumpCard(ColorScheme cs, TextTheme tt) {
    final id = _ctrl.text.trim();
    final show = _isNumericQuery;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: show ? 1 : 0.85,
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        color: show
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: show && id.isNotEmpty ? () => _openById(id) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.tag_rounded, color: cs.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        show ? '编号直达 #$id' : '输入漫画编号可直达详情页',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: show ? cs.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        show ? '点击打开该漫画' : '例如输入 422889 后点击此卡片',
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: show ? cs.primary : cs.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索输入框（圆角填充样式）。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: '搜索名称 / 作者，或输入编号直达',
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  onPressed: onClear,
                ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide(color: cs.primary, width: 1.2),
        ),
        filled: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    );
  }
}
