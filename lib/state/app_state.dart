import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/protocol/jm_api.dart';
import '../core/protocol/jm_client.dart';
import '../core/protocol/jm_domain.dart';
import '../core/protocol/models.dart';
import '../services/download_manager.dart';
import '../services/github_service.dart';
import '../services/local_store.dart';
import '../services/widget_bridge.dart';

/// 阅读方向。
enum ReadDirection { vertical, horizontal, rightToLeft }

/// 全局应用状态：主题 / 阅读设置 / 登录态 / 线路与 DoH / 搜索历史。
class AppState extends ChangeNotifier {
  AppState() {
    // 桌面小组件「刷新」按钮 → 原生拉起 APP（jm_action=widget_refresh）
    // → WidgetBridge 分发 → 重新拉取一批随机推荐写回 widget。
    WidgetBridge.instance.registerAction(
      'widget_refresh',
      (_) => refreshWidgetRandomAlbum(),
    );
  }

  final JmApi api = JmApi.instance;
  final JmClient _c = JmClient.instance;
  final LocalStore _store = LocalStore.instance;

  bool _ready = false;
  bool get ready => _ready;

  // ---------- 主题（对齐 qt 6 套配色） ----------
  ThemeScheme _scheme = ThemeScheme.lightOrange;
  ThemeScheme get scheme => _scheme;

  // ---------- 阅读设置（对齐 qt Setting） ----------
  bool _volumeKeyPaging = true;
  bool get volumeKeyPaging => _volumeKeyPaging;

  ReadDirection _readDirection = ReadDirection.vertical;
  ReadDirection get readDirection => _readDirection;

  bool _keepScreenOn = true;
  bool get keepScreenOn => _keepScreenOn;

  /// 预加载页数（对齐 qt PreLoading）。
  int _preLoad = 5;
  int get preLoad => _preLoad;

  // ---------- 图源 / 语言 ----------
  bool _express = false;
  bool get express => _express;

  String _lang = 'CN';
  String get lang => _lang;

  // ---------- 线路 / DoH（对齐 qt ProxySelectIndex 等） ----------
  int _apiIndex = 1;
  int get apiIndex => _apiIndex;

  int _imgIndex = 1;
  int get imgIndex => _imgIndex;

  bool _enableDoh = false;
  bool get enableDoh => _enableDoh;

  int _dohIndex = 0;
  int get dohIndex => _dohIndex;

  /// 下载根目录（空 = 使用平台默认，Android 为公共下载目录）。
  String _downloadDir = '';
  String get downloadDir => _downloadDir;

  // ---------- 自定义背景（所有页面，阅读器除外） ----------
  String _backgroundPath = '';
  String get backgroundPath => _backgroundPath;
  bool get hasCustomBackground => _backgroundPath.trim().isNotEmpty;

  /// 自定义背景透明度（0.0~1.0，默认 0.5）。
  double _backgroundOpacity = 0.5;
  double get backgroundOpacity => _backgroundOpacity;

  /// 选项透明度（0.0~1.0，默认 1.0 完全不透明）。
  ///
  /// 与背景透明度独立：背景透明度控制自定义壁纸透出程度，
  /// 选项透明度控制前景 UI 元素（卡片/底栏/列表项）的半透明程度，
  /// 用于在背景图较亮时降低前景 UI 的视觉权重以突出背景。
  double _cardOpacity = 1.0;
  double get cardOpacity => _cardOpacity;

  // ---------- 项目 Star 数（GitHub API，进程冷启动请求一次） ----------
  int? _repoStars;
  int? get repoStars => _repoStars;
  bool _starsLoaded = false;

  /// 线路测速结果 host -> 毫秒（-1 失败）。
  Map<String, int> speedResults = <String, int>{};
  bool speedTesting = false;

  // ---------- 登录态 ----------
  LoginData? _user;
  LoginData? get user => _user;
  bool get isLogged => _user != null;

  String? _initError;
  String? get initError => _initError;

  // ---------- 搜索历史 ----------
  List<String> _searchHistory = <String>[];
  List<String> get searchHistory => List<String>.unmodifiable(_searchHistory);

  /// 初始化：恢复持久化设置 → 恢复登录态 → 解析主机并拉取 setting（图床）。
  Future<void> init() async {
    try {
      _scheme = ThemeScheme.fromKey(
        await _store.getString('theme_scheme', 'light_orange'),
      );
      _volumeKeyPaging = await _store.getBool('volume_key_paging', true);
      _readDirection = switch (await _store.getString(
        'read_direction',
        'vertical',
      )) {
        'horizontal' => ReadDirection.horizontal,
        'rightToLeft' => ReadDirection.rightToLeft,
        _ => ReadDirection.vertical,
      };
      _keepScreenOn = await _store.getBool('keep_screen_on', true);
      _preLoad = await _store.getInt('pre_load', 5);
      _express = await _store.getBool('express', false);
      _lang = await _store.getString('lang', 'CN');
      _apiIndex = await _store.getInt('api_index', 1);
      _imgIndex = await _store.getInt('img_index', 1);
      _enableDoh = await _store.getBool('enable_doh', false);
      _dohIndex = await _store.getInt('doh_index', 0);
      _downloadDir = await _store.getString('download_dir', '');
      DownloadManager.instance.customBasePath = _downloadDir;
      _backgroundPath = await _store.getString('custom_background', '');
      // 透明度：默认 0.5，向下兼容老用户（未设置时为 0.5）。
      _backgroundOpacity = await _store.getInt('background_opacity', 50) / 100.0;
      // 限制范围 [0.0, 1.0]
      if (_backgroundOpacity < 0) _backgroundOpacity = 0;
      if (_backgroundOpacity > 1) _backgroundOpacity = 1;
      // 选项透明度：默认 1.0（完全不透明），老用户未设置时也是 1.0。
      _cardOpacity = await _store.getInt('card_opacity', 100) / 100.0;
      if (_cardOpacity < 0) _cardOpacity = 0;
      if (_cardOpacity > 1) _cardOpacity = 1;
      if (_backgroundPath.isNotEmpty && !File(_backgroundPath).existsSync()) {
        // 背景图文件已被删除/清理：静默回落默认背景。
        _backgroundPath = '';
        await _store.remove('custom_background');
      }

      final jwt = await _store.getString('jwt');
      final avs = await _store.getString('avs');
      _c.setAuth(jwt, avs);
      // 服务端 401（token 过期）时同步清除 UI 登录态
      _c.onAuthExpired = () {
        _user = null;
        _store.remove('jwt');
        _store.remove('avs');
        _store.remove('user');
        notifyListeners();
      };
      final userMap = await _store.getJson('user');
      if (userMap.isNotEmpty) {
        _user = LoginData.fromMapSafe(userMap);
      }
      _searchHistory = await _store.getSearchHistory();
    } catch (_) {
      // 设置恢复失败不阻塞启动
    }

    // 主机解析（远程配置更新域名）；图床直接来自 qt PicUrlList 体系
    try {
      await _c.init(
        api: _apiIndex,
        img: _imgIndex,
        language: _lang,
        doh: _enableDoh,
        dohIdx: _dohIndex + 1,
      );
      _ready = true;
      notifyListeners();
    } catch (e) {
      _initError = e.toString();
      _ready = true;
      notifyListeners();
    }

    // 项目 Star 数：仅在进程冷启动的 init() 里请求一次。
    // 切后台再回到前台不会重新走 init()，符合"每次进入 APP 请求一次"的
    // 定义；失败静默（GitHub 在部分网络下不可达，不影响使用）。
    _fetchRepoStars();

    // 桌面小组件数据同步：登录态（如有）+ 随机推荐一次。
    unawaited(WidgetBridge.instance
        .writeUserName(isLogged ? _user!.username : '未登录'));
    unawaited(refreshWidgetRandomAlbum());
  }

  /// 拉取 GitHub 仓库 Star 数（fire-and-forget，失败保留 null）。
  Future<void> _fetchRepoStars() async {
    if (_starsLoaded) return;
    _starsLoaded = true;
    try {
      final stars = await GithubService.fetchStars(
        'Ming-QWQ520',
        'JMComic-Flutter',
      );
      if (stars != null) {
        _repoStars = stars;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---------- 设置项写入 ----------

  Future<void> setScheme(ThemeScheme s) async {
    _scheme = s;
    notifyListeners();
    await _store.setString('theme_scheme', s.key);
  }

  Future<void> setVolumeKeyPaging(bool v) async {
    _volumeKeyPaging = v;
    notifyListeners();
    await _store.setBool('volume_key_paging', v);
  }

  Future<void> setReadDirection(ReadDirection d) async {
    _readDirection = d;
    notifyListeners();
    await _store.setString('read_direction', d.name);
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    notifyListeners();
    await _store.setBool('keep_screen_on', v);
  }

  Future<void> setPreLoad(int v) async {
    _preLoad = v;
    notifyListeners();
    await _store.setInt('pre_load', v);
  }

  Future<void> setExpress(bool v) async {
    _express = v;
    notifyListeners();
    await _store.setBool('express', v);
  }

  Future<void> setLang(String v) async {
    _lang = v;
    _c.lang = v;
    notifyListeners();
    await _store.setString('lang', v);
  }

  /// 切换 API 线路（1..n，对齐 qt ProxySelectIndex）。
  Future<void> setApiIndex(int idx) async {
    _apiIndex = idx;
    _c.apiIndex = idx;
    notifyListeners();
    await _store.setInt('api_index', idx);
  }

  /// 切换图片线路。
  Future<void> setImgIndex(int idx) async {
    _imgIndex = idx;
    _c.imgIndex = idx;
    notifyListeners();
    await _store.setInt('img_index', idx);
  }

  Future<void> setEnableDoh(bool v) async {
    _enableDoh = v;
    _c.enableDoh = v;
    if (!v) _c.clearDns();
    notifyListeners();
    await _store.setBool('enable_doh', v);
  }

  Future<void> setDohIndex(int idx) async {
    _dohIndex = idx;
    _c.dohIndex = idx;
    _c.clearDns();
    notifyListeners();
    await _store.setInt('doh_index', idx);
  }

  /// 修改下载根目录（设置页调用，持久化并即时生效）。
  Future<void> setDownloadDir(String path) async {
    _downloadDir = path.trim();
    DownloadManager.instance.customBasePath = _downloadDir;
    notifyListeners();
    await _store.setString('download_dir', _downloadDir);
  }

  /// 设置自定义背景图（绝对路径；空串 = 恢复默认背景）。
  Future<void> setBackground(String path) async {
    _backgroundPath = path.trim();
    notifyListeners();
    if (_backgroundPath.isEmpty) {
      await _store.remove('custom_background');
    } else {
      await _store.setString('custom_background', _backgroundPath);
    }
  }

  /// 设置背景透明度（0.0~1.0）。
  Future<void> setBackgroundOpacity(double v) async {
    _backgroundOpacity = v.clamp(0.0, 1.0);
    notifyListeners();
    // 持久化为整数百分比（0~100），避免 SharedPreferences 存浮点带来的精度漂移。
    await _store.setInt('background_opacity', (_backgroundOpacity * 100).round());
  }

  /// 设置选项透明度（0.0~1.0）。
  Future<void> setCardOpacity(double v) async {
    _cardOpacity = v.clamp(0.0, 1.0);
    notifyListeners();
    await _store.setInt('card_opacity', (_cardOpacity * 100).round());
  }

  /// 测速全部 API 线路（对齐 qt SpeedTestPingReq）。
  ///
  /// 同时测速所有候选线路（4 个主线路 + CDN + 代理），
  /// 测速键使用与 `_apiOptions`/`_imgOptions` 相同的索引
  /// （1..N 为真实主机，N+1 为 CDN，N+2 为代理）。
  Future<void> testApiSpeed() async {
    if (speedTesting) return;
    speedTesting = true;
    notifyListeners();
    final out = <String, int>{};
    // 1) 主线路：直接 ping 主机。
    final list = JmDomain.apiUrlList.value;
    for (var i = 0; i < list.length; i++) {
      final idx = i + 1;
      out[idx.toString()] = await _c.pingHost(list[i]);
    }
    // 2) CDN 加速线路（索引 5）。
    out['5'] = await _c.pingHost(JmDomain.cdnApiUrl.value);
    // 3) 代理线路（索引 6）。
    out['6'] = await _c.pingHost(JmDomain.proxyApiUrl.value);
    speedResults = out;
    speedTesting = false;
    notifyListeners();
  }

  // ---------- 搜索历史 ----------

  Future<void> addSearchHistory(String keyword) async {
    _searchHistory = await _store.pushSearchHistory(keyword);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory = await _store.clearSearchHistory();
    notifyListeners();
  }

  // ---------- 登录态 ----------

  Future<void> setUser(LoginData user) async {
    _user = user;
    _c.setAuth(user.jwtToken, user.s);
    notifyListeners();
    await _store.setString('jwt', user.jwtToken);
    await _store.setString('avs', user.s);
    await _store.setJson('user', user.toMap());
    // 同步用户名到桌面小组件（widget 显示「用户名」或「未登录」）
    unawaited(WidgetBridge.instance.writeUserName(user.username));
  }

  /// 从服务端拉取最新用户信息并本地落盘（购买/签到后同步 J币等）。
  ///
  /// 静默失败：拉取失败保留本地旧值，不打断操作流。
  Future<void> refreshUser() async {
    if (!isLogged) return;
    try {
      final fresh = await api.getUserProfile();
      if (fresh == null || fresh.id.isEmpty) return;
      // user_profile 不返回 jwt/AVS，保留本地登录态字段。
      final map = fresh.toMap()
        ..['jwttoken'] =
            _user!.jwtToken.isNotEmpty ? _user!.jwtToken : fresh.jwtToken
        ..['s'] = _user!.s.isNotEmpty ? _user!.s : fresh.s;
      final merged = LoginData.fromMap(map);
      _user = merged;
      _c.setAuth(merged.jwtToken, merged.s);
      notifyListeners();
      await _store.setJson('user', merged.toMap());
    } catch (_) {}
  }

  Future<void> clearUser() async {
    _user = null;
    _c.setAuth('', '');
    notifyListeners();
    await _store.remove('jwt');
    await _store.remove('avs');
    await _store.remove('user');
    // 同步退出状态到桌面小组件
    unawaited(WidgetBridge.instance.writeUserName('未登录'));
  }

  /// 拉取一批随机推荐并写入桌面小组件（多页轮播：封面/名称/JM号）。
  ///
  /// 触发时机：APP 冷启动 init()、widget 上点「刷新」（widget_refresh
  /// 动作经原生 → WidgetBridge → 本方法，见构造函数注册）。
  Future<void> refreshWidgetRandomAlbum() async {
    try {
      final list = await api.getRandomRecommend();
      if (list.isEmpty) return;
      final albums = <Map<String, String>>[
        for (final a in list.take(6))
          <String, String>{
            'name': a.name,
            'id': a.id,
            'coverUrl': api.coverUrl(a.id, updateAt: a.updateAt),
          },
      ];
      await WidgetBridge.instance.writeRandomAlbums(albums);
    } catch (_) {
      // 静默失败：widget 不应阻塞主流程
    }
  }
}
