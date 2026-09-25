import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/protocol/jm_api.dart';
import '../core/protocol/jm_client.dart';
import '../core/protocol/jm_domain.dart';
import '../core/protocol/models.dart';
import '../services/download_manager.dart';
import '../services/local_store.dart';

/// 阅读方向。
enum ReadDirection { vertical, horizontal, rightToLeft }

/// 全局应用状态：主题 / 阅读设置 / 登录态 / 线路与 DoH / 搜索历史。
class AppState extends ChangeNotifier {
  AppState();

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

  /// 测速全部 API 线路（对齐 qt SpeedTestPingReq）。
  Future<void> testApiSpeed() async {
    if (speedTesting) return;
    speedTesting = true;
    notifyListeners();
    final out = <String, int>{};
    for (final url in JmDomain.apiUrlList.value) {
      out[url] = await _c.pingHost(url);
    }
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
  }

  Future<void> clearUser() async {
    _user = null;
    _c.setAuth('', '');
    notifyListeners();
    await _store.remove('jwt');
    await _store.remove('avs');
    await _store.remove('user');
  }
}
