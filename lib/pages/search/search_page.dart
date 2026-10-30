import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../state/app_state.dart';
import '../../widgets/album_grid.dart';
import '../../widgets/feedback.dart';
import '../../widgets/liquid_glass_sheet.dart';

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

  /// 测试钩子：单元测试环境下置为 false 可禁用热门标签自动拉取
  /// （避免 widget 测试 FakeAsync 环境产生悬挂网络请求与 pending Timer）。
  @visibleForTesting
  static bool hotTagsFetchEnabled = true;

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

  /// 服务器热门标签（官方 2.1.12 hot_tags 接口，失败时回退静态关键词）。
  List<String> _serverHotTags = <String>[];

  /// 最近一次搜索的结果总数（服务端 total 字段）。
  String _total = '';

  /// 搜索类型（对齐 qt GetSearchReq2 search_type）。
  String _searchType = '';

  /// 长按 1s 后解锁删除模式的历史项下标集合（需求变更：长按历史项
  /// 1 秒后右侧出现 X，点击 X 即删除；点击其它区域退出删除模式）。
  final Set<int> _editingHistory = <int>{};

  /// 长按计时器（每项一个，1s 后把该项加入 _editingHistory）。
  Timer? _longPressTimer;

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
    // JM 服务端搜索排序值 tf（total favorites）：收藏/爱心最多
    'tf': '收藏最多',
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
    // 静默拉取服务器热门标签（对齐官方 2.1.12 FETCH_HOT_TAGS_THUNK）
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHotTags());
  }

  /// 拉取热门标签（hot_tags），失败时静默保留静态关键词。
  Future<void> _loadHotTags() async {
    if (!SearchPage.hotTagsFetchEnabled) return;
    try {
      final data = await JmApi.instance.getHotTags();
      if (!mounted) return;
      final tags = _extractTagNames(data);
      if (tags.isEmpty) return;
      setState(() => _serverHotTags = tags);
    } catch (_) {
      // 静默失败：保留内置热门关键词
    }
  }

  /// 从 hot_tags 响应中宽松提取标签名列表。
  ///
  /// 兼容形态：[{id,name}] / {list:[{name}]} / {data:[{tag_name}]} /
  /// ["标签",...] / {list:["标签",...]}。
  static List<String> _extractTagNames(dynamic data) {
    List<dynamic> raw = const <dynamic>[];
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      for (final key in const <String>['list', 'data', 'tags', 'hot_tags']) {
        final v = data[key];
        if (v is List) {
          raw = v;
          break;
        }
      }
    }
    final out = <String>[];
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) {
        out.add(e.trim());
      } else if (e is Map) {
        final name = e['name'] ?? e['tag'] ?? e['tag_name'] ?? e['title'];
        if (name != null && name.toString().trim().isNotEmpty) {
          out.add(name.toString().trim());
        }
      }
      if (out.length >= 24) break; // 最多展示 24 个
    }
    return out;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
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

  /// 液态玻璃弹出框：排序 + 搜索类型（替代系统 PopupMenu）。
  /// 点击任一选项立即应用并关闭；正在搜索时重新发起搜索。
  Future<void> _showFilterPicker() async {
    final r = await LiquidGlassPicker.show(
      context,
      title: '排序与类型',
      titleIcon: Icons.tune_rounded,
      sections: <GlassSection<Object>>[
        GlassSection<Object>(
          id: 'order',
          title: '排序方式',
          selected: _order,
          options: <GlassOption<Object>>[
            for (final e in _orders.entries)
              GlassOption<Object>(e.key, e.value,
                  icon: e.key == 'mr'
                      ? Icons.schedule_rounded
                      : e.key == 'mv'
                          ? Icons.visibility_outlined
                          : e.key == 'mp'
                              ? Icons.image_outlined
                              : Icons.favorite_rounded),
          ],
        ),
        GlassSection<Object>(
          id: 'type',
          title: '搜索类型',
          selected: _searchType,
          options: <GlassOption<Object>>[
            for (final e in _searchTypes.entries)
              GlassOption<Object>(e.key, e.value,
                  icon: e.key.isEmpty ? Icons.apps_rounded : Icons.label_outline_rounded),
          ],
        ),
      ],
    );
    if (r == null || !mounted) return;
    if (r.sectionId == 'order') {
      setState(() => _order = r.value as String);
    } else if (r.sectionId == 'type') {
      setState(() => _searchType = r.value as String);
    } else {
      return;
    }
    if (_keyword.isNotEmpty) _search(_keyword);
  }

  /// 搜索历史条目（长按 1s 后右侧出现 X，点击 X 删除）。
  ///
  /// 交互细节：
  /// - 按下开始计时 1s；提前松手/移出则取消（不打断正常点击搜索）；
  /// - 计时结束：轻微震动反馈 + 该条目进入编辑态（X 滑入出现）；
  /// - 点击 X：删除该条历史（其后的条目下标左移，编辑态同步清理）；
  /// - 点击任意其它位置/条目：退出编辑态（点击条目仍会正常搜索）。
  Widget _historyChip(int index, String h) {
    final editing = _editingHistory.contains(index);
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      // 长按 1s 计时：onLongPressStart 后等待 1s 再激活编辑态，
      // 而不是系统默认的立即触发（需求变更：长按 1s）。
      onLongPressStart: (_) {
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(seconds: 1), () {
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          setState(() => _editingHistory.add(index));
        });
      },
      onLongPressEnd: (_) => _longPressTimer?.cancel(),
      onLongPressCancel: () => _longPressTimer?.cancel(),
      onLongPressUp: () => _longPressTimer?.cancel(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: editing
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.6),
          ),
          color: editing ? cs.primary.withValues(alpha: 0.08) : null,
        ),
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(100),
              onTap: editing
                  ? () => setState(_editingHistory.clear)
                  : () {
                      _ctrl.text = h;
                      _search(h);
                    },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (editing) ...<Widget>[
                      Icon(Icons.history_rounded,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      h,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
            // 右侧 X：编辑态下滑入出现，点击即删除。
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (Widget child, Animation<double> a) =>
                  FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.4, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: editing
                  ? InkWell(
                      key: ValueKey<String>('del-$h'),
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(100)),
                      onTap: () async {
                        // 删除该条历史（本地存储按值移除）。
                        final app = context.read<AppState>();
                        await app.removeSearchHistory(h);
                        setState(_editingHistory.clear);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            2, 9, 10, 9),
                        child: Icon(Icons.close_rounded,
                            size: 15,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  : const SizedBox(width: 2, key: ValueKey<String>('idle')),
            ),
          ],
        ),
      ),
    );
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
          // 排序 + 搜索类型收纳进同一个液态玻璃弹出框（自定义样式，
          // 替代系统 PopupMenu：透明 + 毛玻璃 + 圆角高光）。
          IconButton(
            tooltip: '排序与类型',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showFilterPicker,
          ),
          // 用户要求去除右上角独立的「搜索」按钮，仅保留筛选按钮
          // 与左侧搜索框。搜索直接通过键盘回车提交，
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

  /// 落地页（精简版）：热门标签（服务器） + 热门搜索 + 搜索历史，其余收纳进顶部菜单。
  Widget _buildLanding(AppState state, ColorScheme cs, TextTheme tt) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_serverHotTags.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: SectionHeader(title: '热门标签')),
              Icon(Icons.local_fire_department_rounded,
                  size: 16, color: cs.primary),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _serverHotTags
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
          const SizedBox(height: 20),
        ],
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '提示：长按条目 1 秒可删除单条历史',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int i = 0; i < state.searchHistory.length; i++)
                _historyChip(i, state.searchHistory[i]),
            ],
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
