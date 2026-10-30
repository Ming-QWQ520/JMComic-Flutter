
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/protocol/jm_api.dart';
import '../../core/protocol/models.dart';
import '../../core/utils/format.dart';
import '../../services/download_manager.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../widgets/entrance.dart';
import '../../widgets/feedback.dart';
import '../../widgets/motion.dart';
import 'album_comment_page.dart';

/// 漫画详情页（JM 官方 App 风格，对齐需求截图）。
///
/// 布局：
/// - 全幅封面头部：封面铺满 + 顶部返回/购买/分享悬浮按钮 +
///   底部渐变遮罩上叠加标题（白）与作者（主题色）；
/// - 通栏主题色「开始阅读」按钮；
/// - 三个页签：漫画介绍 / 目录 / 评论（TabBar 主题色下划线，
///   NestedScrollView 滚动时头部折叠、页签吸顶）；
/// - 介绍页签：喜欢/评论/观看 图标统计 + 收藏/下载/连载通知操作、
///   JM 号编号、描述、标签（#前缀 + ? 帮助）、作者、更多相关；
/// - 多章漫画点下载弹出章节多选（单章漫画直接整本入队）。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage>
    with TickerProviderStateMixin {
  final JmApi _api = JmApi.instance;
  Album? _album;
  bool _loading = true;
  String _error = '';
  String _id = '';
  SearchAlbum? _fallback;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_id.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is SearchAlbum) {
        _fallback = args;
        _id = args.id;
      } else if (args is String) {
        _id = args;
      }
      _load();
    }
  }

  String get _coverUrl {
    if (_album != null) {
      return _api.coverUrl(_album!.id.toString(), updateAt: _album!.updateAt);
    }
    if (_fallback != null) {
      return JmApi.instance.coverUrl(_fallback!.id,
          updateAt: _fallback!.updateAt);
    }
    return '';
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的专辑 ID';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final a = await _api.getAlbum(_id);
      if (!mounted) return;
      setState(() {
        _album = a;
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

  /// 收藏入口：底部弹出收藏夹选择窗（需求：点击收藏时从底部弹出窗口
  /// 让用户选择收藏至哪个收藏夹，顶部是创建收藏夹）。
  ///
  /// 流程对齐 JM 官方 App：
  /// - 拉取收藏夹列表（favorite 接口 folder_list）；
  /// - 弹层顶部为「创建收藏夹」（新建后立即出现在列表中）；
  /// - 点选收藏夹：未收藏时先 addFavorite 收藏，再 moveFavoriteFolder
  ///   移入所选收藏夹；已收藏时仅移动；
  /// - 已收藏状态下提供「取消收藏」入口（addFavorite 切换关闭）。
  Future<void> _toggleFavorite() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    final a = _album!;
    final messenger = ScaffoldMessenger.of(context);
    // 预取收藏夹列表（失败时仅展示默认收藏夹，不阻塞弹层）。
    List<FavoriteFolder> folders = <FavoriteFolder>[];
    try {
      final data = await _api.getFavoriteList(page: 1);
      folders = data.folders;
    } catch (_) {}
    if (!mounted) return;

    final result = await showModalBottomSheet<_FavoriteResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FavoriteSheet(
        api: _api,
        albumId: a.id.toString(),
        folders: folders,
        isFavorite: a.isFavorite,
      ),
    );
    if (result == null) return;
    if (result.unfavorited) {
      setState(() => a.isFavorite = false);
      messenger.showSnackBar(const SnackBar(content: Text('已移出收藏')));
      return;
    }
    setState(() => a.isFavorite = true);
    messenger.showSnackBar(SnackBar(
        content: Text(result.folderName.isEmpty
            ? '收藏成功'
            : '已收藏到「${result.folderName}」')));
  }

  Future<void> _toggleLike() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    final a = _album!;
    try {
      // 点赞（对齐 jmcomic APP API like 端点）
      await _api.miscPost('like', <String, dynamic>{
        'aid': a.id.toString(),
        'type': 'album',
        'action': a.liked ? 'unlike' : 'like',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(a.liked ? '已取消点赞' : '点赞成功')));
      setState(() => a.liked = !a.liked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  /// 下载入口：单章漫画直接整本入队；多章漫画弹出章节多选。
  Future<void> _startDownload() async {
    final a = _album;
    if (a == null) return;
    if (a.series.isEmpty) {
      await _addChapters(<SeriesItem>[]);
      return;
    }
    await _showChapterPicker(a);
  }

  /// 入队指定章节（空列表 = 无章节漫画整本）。
  Future<void> _addChapters(List<SeriesItem> chapters) async {
    final a = _album!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (chapters.isEmpty) {
        await DownloadManager.instance.addEps(
          albumId: a.id.toString(),
          albumName: a.name,
          epsId: a.id.toString(),
          epsName: a.name,
        );
      } else {
        for (final eps in chapters) {
          await DownloadManager.instance.addEps(
            albumId: a.id.toString(),
            albumName: a.name,
            epsId: eps.id,
            epsName: eps.displayTitle,
          );
        }
      }
      messenger.showSnackBar(const SnackBar(content: Text('已加入下载队列')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('加入下载失败: $e')));
    }
  }

  /// 多章漫画下载：底部弹层章节多选（默认全选，可全选/全不选）。
  ///
  /// 此前「下载」对多章漫画不做区分、直接把全部章节加入队列；
  /// 现按需求先选择要下载的章节再入队。
  Future<void> _showChapterPicker(Album a) async {
    final selected = <String>{for (final s in a.series) s.id};
    final confirmed = await showModalBottomSheet<List<SeriesItem>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) =>
          StatefulBuilder(builder: (BuildContext c, void Function(VoidCallback) setSheet) {
        void toggleAll() {
          setSheet(() {
            if (selected.length == a.series.length) {
              selected.clear();
            } else {
              selected
                ..clear()
                ..addAll(a.series.map((s) => s.id));
            }
          });
        }

        void commit() {
          final picked = a.series.where((s) => selected.contains(s.id)).toList();
          Navigator.pop(sheetCtx, picked);
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '选择要下载的章节（${a.series.length} 章）',
                          style: Theme.of(sheetCtx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheet(toggleAll),
                        child: Text(
                          selected.length == a.series.length ? '全不选' : '全选',
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: a.series.length,
                    itemBuilder: (_, i) {
                      final s = a.series[i];
                      return CheckboxListTile(
                        value: selected.contains(s.id),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          s.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('第 ${s.sort} 章'),
                        onChanged: (bool? v) => setSheet(() {
                          v == true
                              ? selected.add(s.id)
                              : selected.remove(s.id);
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: selected.isEmpty ? null : commit,
                          child: Text('下载所选（${selected.length}）'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (confirmed == null || confirmed.isEmpty) return;
    await _addChapters(confirmed);
  }

  void _needLogin() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先登录')));
    Navigator.pushNamed(context, '/login');
  }

  void _openReader({String chapterId = '', int page = 0}) {
    Navigator.pushNamed(
      context,
      '/reader',
      arguments: <String, String>{
        'albumId': _album!.id.toString(),
        'chapterId': chapterId.isEmpty ? _album!.id.toString() : chapterId,
        'title': _album!.name,
        // 单章漫画目录页码直达（0/空 = 从头开始）
        'page': page > 0 ? '$page' : '',
      },
    );
  }

  void _share() {
    final a = _album!;
    StorageService.shareText(
      '「${a.name}」 https://18comic.vip/album/${a.id}',
      title: '分享漫画',
    );
  }

  Future<void> _buyWithCoin() async {
    final app = context.read<AppState>();
    if (!app.isLogged) {
      _needLogin();
      return;
    }
    try {
      await _api.buyComicWithCoin(_album!.id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('购买成功')));
      // 同步刷新：重载专辑详情（已购状态/内容立即生效），
      // 并拉取最新用户资料（J币余额即时更新）。
      context.read<AppState>().refreshUser();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('购买失败: $e')));
    }
  }

  void _copyAlbumId() {
    final a = _album!;
    Clipboard.setData(ClipboardData(text: a.id.toString()));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已复制 JM 号：JM${a.id}')));
  }

  void _showTagHelp() {
    showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('什么是 JM 号？'),
        content: const Text(
          'JM 号即漫画编号（JM 开头数字），可在搜索框中直接输入编号'
          '快速定位漫画，也可把编号分享给其他读者。标签搜索支持输入'
          '任一标签快速筛选同类作品。',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const LoadingView()
          : _error.isNotEmpty
              ? ErrorView(message: _error, onRetry: _load)
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final a = _album!;
    final cs = Theme.of(context).colorScheme;
    return NestedScrollView(
      headerSliverBuilder: (BuildContext c, bool innerBoxScrolled) => <Widget>[
        // 头部：全幅封面 + 悬浮按钮 + 标题/作者 + 通栏开始阅读按钮
        SliverToBoxAdapter(
          child: Column(
            children: <Widget>[
              _HeaderHero(
                coverUrl: _coverUrl,
                title: a.name,
                author: a.authorText,
                albumId: a.id,
                height: _headerHeight(context),
                onBack: () => Navigator.maybePop(context),
                onShare: _share,
                onBuy: _buyWithCoin,
              ),
              // 通栏橙色「开始阅读」（对齐截图：全宽无圆角）
              Material(
                color: cs.primary,
                child: InkWell(
                  onTap: () => _openReader(
                    chapterId: a.series.isEmpty ? '' : a.series.first.id,
                  ),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Text(
                      a.series.isEmpty ? '开始阅读' : '开始阅读（第1话）',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 页签吸顶（对齐截图：漫画介绍 / 目录 / 评论）。
        // SliverOverlapAbsorber 必须包住 pinned 页签栏，
        // 内层 SliverOverlapInjector 才能注入等高内边距。
        SliverOverlapAbsorber(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(c),
          sliver: SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(_tabCtrl),
          ),
        ),
      ],
      body: Builder(
        builder: (BuildContext inner) {
          final handle =
              NestedScrollView.sliverOverlapAbsorberHandleFor(inner);
          return TabBarView(
            controller: _tabCtrl,
            children: <Widget>[
              _IntroTab(
                handle: handle,
                album: a,
                onToggleLike: _toggleLike,
                onToggleFavorite: _toggleFavorite,
                onDownload: _startDownload,
                onOpenComments: () => _tabCtrl.animateTo(2),
                onCopyId: _copyAlbumId,
                onTagHelp: _showTagHelp,
                onOpenWork: (String id) => Navigator.pushReplacementNamed(
                    context, '/album',
                    arguments: id),
              ),
              _CatalogTab(
                handle: handle,
                album: a,
                onOpenReader: _openReader,
              ),
              _CommentsTab(
                handle: handle,
                album: a,
              ),
            ],
          );
        },
      ),
    );
  }

  /// 头部高度：随屏宽自适应（比例对齐截图，约 0.95 宽高比）。
  double _headerHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.95).clamp(340.0, 520.0);
  }
}

/// 吸顶页签栏（含状态栏高度补偿，深色底白字 + 主题色下划线）。
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.controller);

  final TabController controller;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: TabBar(
        controller: controller,
        indicatorColor: cs.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        dividerColor: Colors.transparent,
        tabs: const <Widget>[
          Tab(text: '漫画介绍', height: 48),
          Tab(text: '目录', height: 48),
          Tab(text: '评论', height: 48),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

// ---------------------------------------------------------------------
// 头部：全幅封面 + 悬浮按钮 + 渐变遮罩上的标题/作者
// ---------------------------------------------------------------------

class _HeaderHero extends StatelessWidget {
  const _HeaderHero({
    required this.coverUrl,
    required this.title,
    required this.author,
    required this.albumId,
    required this.height,
    required this.onBack,
    required this.onShare,
    required this.onBuy,
  });

  final String coverUrl;
  final String title;
  final String author;
  final int albumId;
  final double height;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 封面原图：默认只截取封面上半部分（对齐需求"默认截图封面图上半部分"）。
        // 使用 BoxFit.cover + Alignment.topCenter：长封面图自动裁掉下半部，
        // 露出顶部封面图标题区域；用户在详情页内可滚动看到完整封面（PageView）。
        // Hero 封面联动（设置 > 动画设置 > Hero，默认开）：列表端卡片
        // 封面与这里共用同一 tag + 同一图片 URL，点击卡片时封面飞入。
        RepaintBoundary(
          child: HeroCover(
            albumId: '$albumId',
            child: coverUrl.isEmpty
                ? ColoredBox(color: cs.surfaceContainerHighest)
                : ImageStoreCover(
                    url: coverUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
          ),
        ),
        // 渐变遮罩：顶部轻微压暗（悬浮按钮可读）+ 底部重压（标题可读）
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.0, 0.35, 0.62, 1.0],
              colors: <Color>[
                Color(0x66000000),
                Colors.transparent,
                Color(0x59000000),
                Color(0xF2000000),
              ],
            ),
          ),
        ),
        // 悬浮按钮：返回 / J币购买 / 分享
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
                Row(
                  children: <Widget>[
                    _CircleButton(
                        icon: Icons.monetization_on_outlined, onTap: onBuy),
                    const SizedBox(width: 8),
                    _CircleButton(
                        icon: Icons.share_outlined, onTap: onShare),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 底部信息：标题 + 作者（对齐截图：白色标题、主题色作者）
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  shadows: <Shadow>[
                    Shadow(blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  shadows: const <Shadow>[
                    Shadow(blurRadius: 6, color: Colors.black87),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

/// 头部半透明圆形按钮。
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black26,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 介绍页签
// ---------------------------------------------------------------------

class _IntroTab extends StatelessWidget {
  const _IntroTab({
    required this.handle,
    required this.album,
    required this.onToggleLike,
    required this.onToggleFavorite,
    required this.onDownload,
    required this.onOpenComments,
    required this.onCopyId,
    required this.onTagHelp,
    required this.onOpenWork,
  });

  final SliverOverlapAbsorberHandle handle;
  final Album album;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDownload;
  final VoidCallback onOpenComments;
  final VoidCallback onCopyId;
  final VoidCallback onTagHelp;
  final void Function(String id) onOpenWork;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final authors = album.authorText
        .split(RegExp(r'[,，、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '佚名')
        .toList();

    return Builder(
      builder: (BuildContext c) => CustomScrollView(
        key: const PageStorageKey<String>('intro-tab'),
        slivers: <Widget>[
          SliverOverlapInjector(handle: handle),
          // ---------- 图标操作行（横向铺满全宽，不留左右留白） ----------
          SliverToBoxAdapter(
            child: Entrance(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                ),
                child: Row(
                  children: <Widget>[
                    _IconAction(
                      icon: album.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      iconColor: album.liked
                          ? const Color(0xFFFF5A78)
                          : cs.onSurfaceVariant,
                      label: '${formatCount(album.totalLikes)}喜欢',
                      onTap: onToggleLike,
                    ),
                    _IconAction(
                      icon: Icons.chat_bubble_outline_rounded,
                      label:
                          '${album.commentTotal > 0 ? formatCount(album.commentTotal) : ''}评论',
                      onTap: onOpenComments,
                    ),
                    _IconAction(
                      icon: Icons.visibility_outlined,
                      label: '${formatCount(album.totalViews)}观看',
                    ),
                    _IconAction(
                      icon: album.isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      iconColor:
                          album.isFavorite ? cs.primary : cs.onSurfaceVariant,
                      label: '收藏',
                      onTap: onToggleFavorite,
                    ),
                    _IconAction(
                      icon: Icons.download_outlined,
                      label: '下载',
                      onTap: onDownload,
                    ),
                    _IconAction(
                      icon: Icons.notifications_none_rounded,
                      label: '连载通知',
                      onTap: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                              content: Text('连载通知请在网页端设置'))),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.list(
              children: <Widget>[
                const SizedBox(height: 0),
                // ---------- JM 号 ----------
                Entrance(
                  delay: const Duration(milliseconds: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'JM 号',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: onCopyId,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'JM${album.id}',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.primary,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('页数：${album.totalPhotos}',
                          style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                // ---------- 描述 ----------
                if (album.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Entrance(
                    delay: const Duration(milliseconds: 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '描述',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stripHtmlTags(album.description),
                          style: tt.bodyMedium?.copyWith(height: 1.65),
                        ),
                      ],
                    ),
                  ),
                ],
                // ---------- 标签 ----------
                if (album.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Entrance(
                    delay: const Duration(milliseconds: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(
                              '标签',
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(100),
                              onTap: onTagHelp,
                              child: Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.question_mark_rounded,
                                    size: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: album.tags
                              .map(
                                (String t) => InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => Navigator.pushNamed(
                                      context, '/search',
                                      arguments: t),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      '#$t',
                                      style: TextStyle(
                                          fontSize: 13, color: cs.onSurface),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
                // ---------- 作者 ----------
                if (authors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Entrance(
                    delay: const Duration(milliseconds: 160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '作者',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: authors
                              .map(
                                (String a) => InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => Navigator.pushNamed(
                                      context, '/search',
                                      arguments: a),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: cs.outlineVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      '#$a',
                                      style: TextStyle(
                                          fontSize: 13, color: cs.onSurface),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
                // ---------- 更多相关 ----------
                if (album.works.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Entrance(
                    delay: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '更多相关',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          ...album.works.map(
                            (AlbumWorks w) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.collections_bookmark_outlined,
                                color: cs.primary,
                                size: 20,
                              ),
                              title: Text(
                                w.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                              onTap: () => onOpenWork(w.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 图标操作项（统计/操作通用，对齐截图：图标在上、文字在下）。
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = iconColor ?? cs.onSurface;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 目录页签：无章节 = 页码网格；有章节 = 章节列表
// ---------------------------------------------------------------------

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({
    required this.handle,
    required this.album,
    required this.onOpenReader,
  });

  final SliverOverlapAbsorberHandle handle;
  final Album album;
  final void Function({String chapterId, int page}) onOpenReader;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Builder(
      builder: (BuildContext c) => CustomScrollView(
        key: const PageStorageKey<String>('catalog-tab'),
        slivers: <Widget>[
          SliverOverlapInjector(handle: handle),
          if (album.series.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverMainAxisGroup(
                slivers: <Widget>[
                  // 单章漫画（无章节列表）说明：这里的数字是页码而非章节，
                  // 点击可直达对应页。
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '单章作品 · 共 ${album.totalPhotos} 页（点击页码直达该页）',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 88,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext c, int i) {
                        return Material(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onOpenReader(page: i + 1),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: album.totalPhotos,
                    ),
                  ),
                ],
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              sliver: SliverList.separated(
                itemCount: _chapterGroupCount(album.series.length),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext c, int i) {
                  final group = _chapterGroupAt(album.series, i);
                  if (group.length == 1) {
                    // 单章分组：直接显示为单条章节卡片。
                    final s = group.first;
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            s.sort,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          s.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                        onTap: () => onOpenReader(chapterId: s.id),
                      ),
                    );
                  }
                  // 多章合并分组（每 10 话合并为 x~x 话卡片）：
                  // 点击弹出展开列表，从中选一章进入阅读。
                  return _ChapterGroupCard(
                    group: group,
                    onOpenReader: onOpenReader,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 按每 10 话一组对章节列表分组，返回分组总数。
/// - 第 1 组：第 1~10 章（≤ 10 章）
/// - 第 2 组：第 11~20 章
/// - …
/// - 最后一组：余下的章节数（可能是 1~10 章）
int _chapterGroupCount(int total) {
  if (total <= 0) return 0;
  return (total + 9) ~/ 10;
}

/// 取第 [groupIndex] 个分组（0-indexed）内的章节列表。
List<SeriesItem> _chapterGroupAt(List<SeriesItem> series, int groupIndex) {
  final start = groupIndex * 10;
  final end = (start + 10).clamp(0, series.length);
  if (start >= series.length) return <SeriesItem>[];
  return series.sublist(start, end);
}

/// 章节合并卡片：显示「第 x~x 话 · N 章」标题，点击展开为子列表。
class _ChapterGroupCard extends StatefulWidget {
  const _ChapterGroupCard({
    required this.group,
    required this.onOpenReader,
  });

  final List<SeriesItem> group;

  final void Function({String chapterId, int page}) onOpenReader;

  @override
  State<_ChapterGroupCard> createState() => _ChapterGroupCardState();
}

class _ChapterGroupCardState extends State<_ChapterGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = widget.group.first;
    final last = widget.group.last;
    final label = first.sort == last.sort
        ? '第${first.sort}话'
        : '第${first.sort}~${last.sort}话';
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            leading: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.menu_book_rounded,
                  size: 18, color: cs.primary),
            ),
            title: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${widget.group.length} 章'),
            trailing: Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: cs.onSurfaceVariant,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: <Widget>[
                  for (final s in widget.group)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      leading: Text(
                        s.sort,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      title: Text(
                        s.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () =>
                          widget.onOpenReader(chapterId: s.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 评论页签：复用评论页（embedded 内嵌模式，无独立 Scaffold）。
// 内层不是滚动视图，用 handle.layoutExtent 动态让出吸顶页签的位置。
// ---------------------------------------------------------------------

class _CommentsTab extends StatelessWidget {
  const _CommentsTab({required this.handle, required this.album});

  final SliverOverlapAbsorberHandle handle;
  final Album album;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: handle,
      builder: (BuildContext c, Widget? w) => Padding(
        padding: EdgeInsets.only(top: handle.layoutExtent ?? 0),
        child: w,
      ),
      child: AlbumCommentPage(
        key: PageStorageKey<String>('comments-${album.id}'),
        albumId: album.id.toString(),
        albumName: album.name,
        embedded: true,
      ),
    );
  }
}

/// 详情页封面（走 ImageStore 统一加载，含 `_3x4` 回退与魔数校验）。
class ImageStoreCover extends StatefulWidget {
  const ImageStoreCover({super.key, required this.url, this.fit, this.alignment});

  final String url;
  final BoxFit? fit;

  /// 图片对齐方式（默认 Alignment.center）。
  /// 详情页头部使用 Alignment.topCenter 以截取长封面图的顶部。
  final Alignment? alignment;

  @override
  State<ImageStoreCover> createState() => _ImageStoreCoverState();
}

class _ImageStoreCoverState extends State<ImageStoreCover> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = ImageStore.instance.load(widget.url);
  }

  @override
  void didUpdateWidget(ImageStoreCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = ImageStore.instance.load(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (BuildContext c, AsyncSnapshot<Uint8List?> snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: snap.connectionState == ConnectionState.waiting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.broken_image_outlined, color: cs.outline),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit ?? BoxFit.cover,
          alignment: widget.alignment ?? Alignment.center,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// 收藏操作结果（弹层回传给详情页）。
class _FavoriteResult {
  const _FavoriteResult._({this.unfavorited = false, this.folderName = ''});

  /// 取消收藏。
  const _FavoriteResult.unfavorite() : this._(unfavorited: true);

  /// 收藏到指定名称的收藏夹（空 = 默认收藏夹）。
  const _FavoriteResult.favorite(String name)
      : this._(folderName: name);

  final bool unfavorited;
  final String folderName;
}

/// 收藏夹选择底部弹层（JM 官方 App 风格）。
///
/// 结构：
/// - 顶部：标题「收藏到收藏夹」+ 关闭按钮；
/// - 「创建收藏夹」入口（新建后立即插入列表并选中态提示）；
/// - 收藏夹列表：默认收藏 + 用户自建收藏夹；
/// - 已收藏状态下底部提供「取消收藏」。
class _FavoriteSheet extends StatefulWidget {
  const _FavoriteSheet({
    required this.api,
    required this.albumId,
    required this.folders,
    required this.isFavorite,
  });

  final JmApi api;
  final String albumId;
  final List<FavoriteFolder> folders;
  final bool isFavorite;

  @override
  State<_FavoriteSheet> createState() => _FavoriteSheetState();
}

class _FavoriteSheetState extends State<_FavoriteSheet> {
  late final List<FavoriteFolder> _folders =
      List<FavoriteFolder>.from(widget.folders);
  bool _busy = false;

  Future<void> _pop(_FavoriteResult r) async {
    Navigator.pop(context, r);
  }

  /// 创建收藏夹（顶部入口）。
  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('创建收藏夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '收藏夹名称'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.addFavoriteFolder(name);
      if (!mounted) return;
      setState(() {
        _folders.add(FavoriteFolder.fromMap(<String, dynamic>{
          'fid': '${DateTime.now().millisecondsSinceEpoch}',
          'name': name,
        }));
        _busy = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已创建「$name」，点击它完成收藏')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  /// 收藏到所选收藏夹：未收藏先收藏，再移动；已收藏仅移动。
  Future<void> _favoriteTo(FavoriteFolder? folder) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!widget.isFavorite) {
        await widget.api.addFavorite(widget.albumId);
      }
      if (folder != null) {
        await widget.api.moveFavoriteFolder(widget.albumId, folder.fid);
      }
      if (!mounted) return;
      await _pop(_FavoriteResult.favorite(folder?.name ?? ''));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('收藏失败: $e')));
    }
  }

  /// 取消收藏（addFavorite 为切换式接口）。
  Future<void> _unfavorite() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.addFavorite(widget.albumId);
      if (!mounted) return;
      await _pop(const _FavoriteResult.unfavorite());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
                color: cs.primary.withValues(alpha: 0.35), width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // —— 拖拽把手 ——
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              // —— 标题行 ——
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.bookmark_rounded,
                          size: 18, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('收藏到收藏夹',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: cs.onSurfaceVariant),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // —— 创建收藏夹（顶部入口） ——
              InkWell(
                borderRadius: BorderRadius.circular(0),
                onTap: _busy ? null : _createFolder,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.5),
                          ),
                          color: cs.primary.withValues(alpha: 0.06),
                        ),
                        child: Icon(Icons.create_new_folder_outlined,
                            size: 19, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('创建收藏夹',
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Icon(Icons.add_rounded, size: 20, color: cs.primary),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // —— 收藏夹列表 ——
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.42,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: <Widget>[
                      _folderTile(
                        icon: Icons.folder_special_outlined,
                        name: '默认收藏',
                        onTap: () => _favoriteTo(null),
                      ),
                      for (final FavoriteFolder f in _folders)
                        _folderTile(
                          icon: Icons.folder_outlined,
                          name: f.name,
                          onTap: () => _favoriteTo(f),
                        ),
                    ],
                  ),
                ),
              ),
              // —— 取消收藏（已收藏时） ——
              if (widget.isFavorite) ...<Widget>[
                const Divider(height: 1),
                InkWell(
                  onTap: _busy ? null : _unfavorite,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.bookmark_remove_outlined,
                            size: 18, color: cs.error),
                        const SizedBox(width: 6),
                        Text('取消收藏',
                            style: tt.bodyMedium
                                ?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folderTile({
    required IconData icon,
    required String name,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
