import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';

/// 搜索页。
///
/// 交互（精简后）：
/// - 输入纯数字（漫画编号）提交 → 直接跳转对应漫画详情页；
///   编号不存在时自动回退为关键词搜索；
/// - 输入名称/关键词提交 → 常规搜索；
/// - 落地页只保留「热门搜索 + 搜索历史」两组内容，
///   排序与搜索类型收纳进右上角单一条目，避免首屏信息过载。
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

  /// 最近一次搜索的结果总数（服务端 total 字段）。
  String _total = '';

  /// 搜索类型（对齐 qt GetSearchReq2 search_type）。
  String _searchType = '';

  static const Map<String, String> _searchTypes = <String, String>{
    '': '全部',
    'tag': '标签',
    'author': '作者',
    'work': '作品',
    'character': '角色',
  };

  static const Map<String, String> _orders = <String, String>{
    'mr': '最新',
    'mv': '最多点击',
    'mp': '最多图片',
    'tf': '最多爱心',
  };

  /// 热门搜索（点击即搜，对齐 qt 搜索页快捷标签）。
  static const List<String> _hotKeywords = <String>[
    '巨乳',
    '姐姐',
    '妹妹',
    '人妻',
    '校园',
    '纯爱',
    '女王',
    '女仆',
    '御姐',
    '萝莉',
    '办公室',
    '后宫',
    '束缚',
    '教师',
    '护士',
    '巫女',
    '触手',
    '异世界',
  ];

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

  /// 输入是否为纯数字（漫画编号，3~12 位）。
  bool _isNumeric(String s) => RegExp(r'^\d{3,12}$').hasMatch(s);

  Future<void> _search([String? kw]) async {
    final k = (kw ?? _ctrl.text).trim();
    if (k.isEmpty) return;
    _focus.unfocus();

    // 编号直达：纯数字优先按漫画编号打开详情页。
    if (_isNumeric(k)) {
      final opened = await _openById(k);
      if (opened) return;
      // 编号不存在/打开失败 → 回退为关键词搜索，不打断用户。
    }

    if (!mounted) return;
    setState(() {
      _keyword = k;
      _ctrl.text = k;
      _total = '';
      _grid = AlbumGrid(
        key: ValueKey<String>('search-$k-$_order-$_searchType'),
        fetchPage: _fetch,
      );
    });
    await context.read<AppState>().addSearchHistory(k);
  }

  Future<List<SearchAlbum>?> _fetch(int page) async {
    // 异常直接抛给 AlbumGrid，展示真实错误详情
    final r = await JmApi.instance.searchComic(
      _keyword,
      page,
      order: _order,
      searchType: _searchType,
    );
    if (mounted && page == 1) {
      setState(() => _total = r.total);
    }
    return r.content;
  }

  /// 编号直达：查详情成功后进入详情页。
  /// 返回是否成功；失败时提示并允许回退关键词搜索。
  Future<bool> _openById(String id) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final album = await JmApi.instance.getAlbum(id);
      if (album.id == 0) throw StateError('专辑不存在');
      navigator.pushNamed('/album', arguments: album.id.toString());
      return true;
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text('编号 #$id 不存在或加载失败，已按关键词搜索'),
        duration: const Duration(seconds: 2),
      ));
      return false;
    }
  }

  void _clear() {
    _focus.unfocus();
    setState(() {
      _ctrl.clear();
      _keyword = '';
      _total = '';
      _grid = null;
    });
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
          onClear: _clear,
        ),
        actions: [
          // 排序 + 搜索类型收纳进同一个菜单，精简首屏。
          PopupMenuButton<String>(
            tooltip: '排序与类型',
            icon: const Icon(Icons.tune_rounded),
            onSelected: (String v) {
              if (v.startsWith('order:')) {
                setState(() => _order = v.substring(6));
              } else if (v.startsWith('type:')) {
                setState(() => _searchType = v.substring(5));
              } else {
                return;
              }
              if (_keyword.isNotEmpty) _search(_keyword);
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('排序', style: TextStyle(fontSize: 12)),
              ),
              for (final e in _orders.entries)
                PopupMenuItem<String>(
                  value: 'order:${e.key}',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: _order == e.key
                            ? Icon(Icons.check_rounded,
                                size: 17, color: cs.primary)
                            : null,
                      ),
                      Text(e.value),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('搜索类型', style: TextStyle(fontSize: 12)),
              ),
              for (final e in _searchTypes.entries)
                PopupMenuItem<String>(
                  value: 'type:${e.key}',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: _searchType == e.key
                            ? Icon(Icons.check_rounded,
                                size: 17, color: cs.primary)
                            : null,
                      ),
                      Text(e.value),
                    ],
                  ),
                ),
            ],
          ),
          // 用户要求去除右上角独立的「搜索」按钮，仅保留筛选按钮
          // (PopupMenuButton) 与左侧搜索框。搜索直接通过键盘回车提交，
          // 或在搜索框右侧的 clear/submit 入口处理。
          const SizedBox(width: 4),
        ],
      ),
      body: _grid != null
          ? Column(
              children: [
                if (_total.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(
                      children: [
                        // Flexible + ellipsis：长关键词不再把 Row 撑出溢出条纹。
                        Flexible(
                          child: Text(
                            '「$_keyword」',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '共 $_total 个结果',
                          style: tt.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _grid!),
              ],
            )
          : _buildLanding(state, cs, tt),
    );
  }

  /// 落地页（精简版）：热门搜索 + 搜索历史，其余收纳进顶部菜单。
  Widget _buildLanding(AppState state, ColorScheme cs, TextTheme tt) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(title: '热门搜索'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotKeywords
              .map(
                (String h) => ActionChip(
                  label: Text(h),
                  labelStyle: const TextStyle(fontSize: 12.5),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _ctrl.text = h;
                    _search(h);
                  },
                ),
              )
              .toList(),
        ),
        if (state.searchHistory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: SectionHeader(title: '搜索历史')),
              IconButton(
                tooltip: '清空历史',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: () => context.read<AppState>().clearSearchHistory(),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.searchHistory
                .map(
                  (String h) => ActionChip(
                    label: Text(h),
                    labelStyle: const TextStyle(fontSize: 12.5),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _ctrl.text = h;
                      _search(h);
                    },
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '提示：输入漫画编号（纯数字）可直接打开详情页',
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
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
        hintText: '搜索名称 / 作者 / 编号',
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    );
  }
}
