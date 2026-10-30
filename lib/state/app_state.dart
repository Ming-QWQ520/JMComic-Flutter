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

/// 阅读方向。
enum ReadDirection { vertical, horizontal, rightToLeft }

/// 全局应用状态：主题 / 阅读设置 / 登录态 / 线路与 DoH / 搜索历史。
class AppState extends ChangeNotifier {
  AppState() {
    // 同步预载全部个性化设置（main() 已在 runApp 前 warmUp SharedPreferences，
    // 同步读取直接命中缓存）——保证首帧就是保存的主题/背景/透明度，
    // 而不是"先默认样式、init 完成后再跳变"。
    // 需求变更：默认主题跟随系统（未设置过 theme_mode 时取系统明暗）。
    final savedMode = _store.getStringSync('theme_mode', '');
    _themeMode = switch (savedMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    // 旧版 scheme key（light_orange/dark_orange/pink）不再读取：
    // theme_mode 为准；用户下次改主题时会覆盖写入新 key。
    _scheme = _resolveScheme();
    _listenSystemBrightness();
    _anim = AnimationOptions.fromMap(<String, Object>{
      'anim_page_transitions': _store.getBoolSync('anim_page_transitions', true),
      'anim_hero': _store.getBoolSync('anim_hero', true),
      'anim_physics': _store.getBoolSync('anim_physics', false),
      'anim_card3d': _store.getBoolSync('anim_card3d', false),
    });
    _volumeKeyPaging = _store.getBoolSync('volume_key_paging', true);
    _readDirection = switch (_store.getStringSync('read_direction', 'vertical')) {
      'horizontal' => ReadDirection.horizontal,
      'rightToLeft' => ReadDirection.rightToLeft,
      _ => ReadDirection.vertical,
    };
    _keepScreenOn = _store.getBoolSync('keep_screen_on', true);
    _preLoad = _store.getIntSync('pre_load', 5);
    _express = _store.getBoolSync('express', false);
    _lang = _store.getStringSync('lang', 'CN');
    _apiIndex = _store.getIntSync('api_index', 1);
    _imgIndex = _store.getIntSync('img_index', 1);
    _enableDoh = _store.getBoolSync('enable_doh', false);
    _dohIndex = _store.getIntSync('doh_index', 0);
    _downloadDir = _store.getStringSync('download_dir', '');
    DownloadManager.instance.customBasePath = _downloadDir;
    _backgroundPath = _store.getStringSync('custom_background', '');
    if (_backgroundPath.isNotEmpty && !File(_backgroundPath).existsSync()) {
      // 背景图文件已被删除/清理：静默回落默认背景。
      _backgroundPath = '';
    }
    _backgroundOpacity =
        _store.getIntSync('background_opacity', 50) / 100.0;
    if (_backgroundOpacity < 0) _backgroundOpacity = 0;
    if (_backgroundOpacity > 1) _backgroundOpacity = 1;
    _cardOpacity = _store.getIntSync('card_opacity', 100) / 100.0;
    if (_cardOpacity < 0) _cardOpacity = 0;
    if (_cardOpacity > 1) _cardOpacity = 1;
    _appLockEnabled = _store.getBoolSync('app_lock_enabled', false);
    _readerLineButton = _store.getBoolSync('reader_line_button', true);
  }

  final JmApi api = JmApi.instance;
  final JmClient _c = JmClient.instance;
  final LocalStore _store = LocalStore.instance;

  bool _ready = false;
  bool get ready => _ready;

  // ---------- 主题（青色双方案 + 跟随系统） ----------
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// 当前生效方案（跟随系统时按系统明暗解析）。
  ThemeScheme _scheme = ThemeScheme.lightTeal;
  ThemeScheme get scheme => _scheme;

  /// 按当前 themeMode 与系统明暗解析生效方案。
  ThemeScheme _resolveScheme() {
    final bool dark;
    switch (_themeMode) {
      case ThemeMode.light:
        dark = false;
      case ThemeMode.dark:
        dark = true;
      case ThemeMode.system:
        dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
    return dark ? ThemeScheme.darkTeal : ThemeScheme.lightTeal;
  }

  /// 监听系统明暗变化：跟随系统模式下实时切换深浅主题。
  void _listenSystemBrightness() {
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      if (_themeMode != ThemeMode.system) return;
      final next = _resolveScheme();
      if (next == _scheme) return;
      _scheme = next;
      notifyListeners();
    };
  }

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

  // ---------- 应用锁（local_auth：指纹/面容/锁屏密码） ----------
  /// 开启后：冷启动与切后台返回时要求本地认证解锁。
  bool _appLockEnabled = false;
  bool get appLockEnabled => _appLockEnabled;

  // ---------- 动画设置（设置 > 动画设置） ----------
  /// 四类动效开关，默认只开「页面转场 + Hero」。
  AnimationOptions _anim = AnimationOptions();
  AnimationOptions get anim => _anim;

  /// 写入单个动画开关并持久化。
  Future<void> setAnimOption({
    bool? pageTransitions,
    bool? hero,
    bool? physics,
    bool? card3d,
  }) async {
    if (pageTransitions != null) {
      _anim.pageTransitions = pageTransitions;
      await _store.setBool('anim_page_transitions', pageTransitions);
    }
    if (hero != null) {
      _anim.heroEnabled = hero;
      await _store.setBool('anim_hero', hero);
    }
    if (physics != null) {
      _anim.physicsAnimations = physics;
      await _store.setBool('anim_physics', physics);
    }
    if (card3d != null) {
      _anim.card3d = card3d;
      await _store.setBool('anim_card3d', card3d);
    }
    notifyListeners();
  }

  /// 写入应用锁开关（设置页在本地认证通过后才调用）。
  Future<void> setAppLockEnabled(bool v) async {
    _appLockEnabled = v;
    notifyListeners();
    await _store.setBool('app_lock_enabled', v);
  }

  /// 阅读界面常驻线路切换按键（左下角）开关，默认开启。
  bool _readerLineButton = true;
  bool get readerLineButton => _readerLineButton;

  Future<void> setReaderLineButton(bool v) async {
    _readerLineButton = v;
    notifyListeners();
    await _store.setBool('reader_line_button', v);
  }

  // ---------- 项目数据（GitHub API，进程冷启动请求一次） ----------
  int? _repoStars;
  int? get repoStars => _repoStars;

  /// 仓库简介（GitHub API description，关于页展示用）。
  String? _repoDescription;
  String? get repoDescription => _repoDescription;

  /// 开源协议 SPDX ID（GitHub API，仓库未声明时为 null）。
  String? _repoLicense;
  String? get repoLicense => _repoLicense;

  bool _starsLoaded = false;

  /// 线路测速结果 host -> 毫秒（-1 失败）。
  Map<String, int> speedResults = <String, int>{};
  bool speedTesting = false;

  /// 图片线路测速结果（键与 [speedResults] 相同：1..N 主机、5 CDN、6 代理）。
  Map<String, int> imgSpeedResults = <String, int>{};

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
      final savedMode = await _store.getString('theme_mode', '');
      _themeMode = switch (savedMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _scheme = _resolveScheme();
      _anim = AnimationOptions.fromMap(<String, Object>{
        'anim_page_transitions':
            await _store.getBool('anim_page_transitions', true),
        'anim_hero': await _store.getBool('anim_hero', true),
        'anim_physics': await _store.getBool('anim_physics', false),
        'anim_card3d': await _store.getBool('anim_card3d', false),
      });
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
  }

  /// 拉取 GitHub 仓库元信息：Star 数 + 简介（fire-and-forget，失败保留 null）。
  Future<void> _fetchRepoStars() async {
    if (_starsLoaded) return;
    _starsLoaded = true;
    try {
      final meta = await GithubService.fetchRepoMeta();
      if (meta == null) return;
      _repoStars = meta.stars;
      _repoDescription =
          (meta.description ?? '').trim().isEmpty ? null : meta.description;
      _repoLicense = meta.license;
      notifyListeners();
    } catch (_) {}
  }

  // ---------- 设置项写入 ----------

  /// 切换主题模式（跟随系统/浅色/深色），持久化并即时生效。
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _scheme = _resolveScheme();
    notifyListeners();
    await _store.setString('theme_mode', mode.name);
    // 同步写入 scheme key，保持旧字段语义一致（清理/回滚友好）。
    await _store.setString('theme_scheme', _scheme.key);
  }

  /// 兼容入口：直接选择深/浅方案（等价于显式设定对应主题模式）。
  Future<void> setScheme(ThemeScheme s) async => setThemeMode(
        s.isDark ? ThemeMode.dark : ThemeMode.light,
      );

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

  /// 线路测速（对齐 qt SpeedTestPingReq：HEAD 请求计时）。
  ///
  /// 并行测试 API 线路与图片线路（各含 4 个主线路 + CDN5 + 代理6），
  /// 结果分别写入 [speedResults] / [imgSpeedResults]，键为线路索引
  /// （1..N 为真实主机，5 为 CDN，6 为代理，与设置页/阅读器选项一致）。
  Future<void> testApiSpeed() async {
    if (speedTesting) return;
    speedTesting = true;
    notifyListeners();
    final out = <String, int>{};
    final outImg = <String, int>{};
    final jobs = <Future<void>>[];
    // API 线路：主线路 1..N 并行。
    final apiList = JmDomain.apiUrlList.value;
    for (var i = 0; i < apiList.length; i++) {
      final idx = (i + 1).toString();
      jobs.add(_c.pingHost(apiList[i]).then((v) => out[idx] = v));
    }
    jobs.add(
      _c.pingHost(JmDomain.cdnApiUrl.value).then((v) => out['5'] = v),
    );
    jobs.add(
      _c.pingHost(JmDomain.proxyApiUrl.value).then((v) => out['6'] = v),
    );
    // 图片线路：与 API 线路同索引语义，一次测速同时出结果。
    final imgList = JmDomain.picUrlList.value;
    for (var i = 0; i < imgList.length; i++) {
      final idx = (i + 1).toString();
      jobs.add(_c.pingHost(imgList[i]).then((v) => outImg[idx] = v));
    }
    jobs.add(
      _c.pingHost(JmDomain.cdnImgUrl.value).then((v) => outImg['5'] = v),
    );
    jobs.add(
      _c.pingHost(JmDomain.proxyImgUrl.value).then((v) => outImg['6'] = v),
    );
    await Future.wait(jobs);
    speedResults = out;
    imgSpeedResults = outImg;
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

  /// 删除单条搜索历史（搜索页长按条目后点 X）。
  Future<void> removeSearchHistory(String keyword) async {
    _searchHistory = await _store.removeSearchHistory(keyword);
    notifyListeners();
  }

  // ---------- 登录态 ----------

  Future<void> setUser(LoginData user) async {
    _user = user;
    // 关键修复（浏览历史无内容的根因）：
    // login() 已从响应 Set-Cookie 中捕获 AVS 并写入 client，而 login
    // 响应 data 内并无 s/AVS 字段（对齐 qt ParseLogin2，只有 jwttoken）。
    // 此处原来直接 setAuth(user.jwtToken, user.s) 会用空串覆盖掉刚
    // 捕获的 AVS Cookie，导致 watch_list 等需要会话 Cookie 的接口
    // 返回 401，表现为「浏览历史无内容」。
    final avs = _c.avs.isNotEmpty ? _c.avs : user.s;
    final jwt = user.jwtToken.isNotEmpty ? user.jwtToken : _c.jwt;
    _c.setAuth(jwt, avs);
    notifyListeners();
    await _store.setString('jwt', jwt);
    await _store.setString('avs', avs);
    await _store.setJson('user', user.toMap());
  }

  /// 从服务端拉取最新用户信息并本地落盘（购买/签到后同步 J币等）。
  ///
  /// 静默失败：拉取失败保留本地旧值，不打断操作流。
  Future<void> refreshUser() async {
    if (!isLogged) return;
    try {
      final fresh = await api.getUserProfile();
      if (fresh == null || fresh.id.isEmpty) return;
      // user_profile 不返回 jwt/AVS；s 字段同样缺失，保留 client 当前
      // 登录态字段（含 Cookie 捕获的 AVS），避免合并后被空串覆盖。
      final map = fresh.toMap()
        ..['jwttoken'] =
            _user!.jwtToken.isNotEmpty ? _user!.jwtToken : fresh.jwtToken
        ..['s'] = _c.avs.isNotEmpty ? _c.avs : _user!.s;
      final merged = LoginData.fromMap(map);
      _user = merged;
      _c.setAuth(merged.jwtToken, merged.s.isNotEmpty ? merged.s : _c.avs);
      notifyListeners();
      await _store.setJson('user', merged.toMap());
    } catch (_) {}
  }

  Future<void> clearUser() async {
    // 对齐官方 2.1.12：退出前调用 POST /logout 注销服务端会话
    // （api.logout() 内部静默吞掉网络异常，不阻塞本地退出）。
    if (isLogged) {
      await api.logout();
    }
    _user = null;
    _c.setAuth('', '');
    notifyListeners();
    await _store.remove('jwt');
    await _store.remove('avs');
    await _store.remove('user');
  }
}
