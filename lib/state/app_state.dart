import 'package:flutter/material.dart';

import '../core/protocol/jm_api.dart';
import '../core/protocol/jm_client.dart';
import '../core/protocol/models.dart';
import '../services/local_store.dart';

/// 阅读方向。
enum ReadDirection { vertical, horizontal }

/// 全局应用状态：主题模式 / 阅读设置 / 登录态 / 图源与语言 / 搜索历史。
class AppState extends ChangeNotifier {
  AppState();

  final JmApi api = JmApi.instance;
  final JmClient _c = JmClient.instance;
  final LocalStore _store = LocalStore.instance;

  bool _ready = false;
  bool get ready => _ready;

  // ---------- 主题（默认跟随系统） ----------
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // ---------- 阅读设置 ----------
  bool _volumeKeyPaging = true;
  bool get volumeKeyPaging => _volumeKeyPaging;

  ReadDirection _readDirection = ReadDirection.vertical;
  ReadDirection get readDirection => _readDirection;

  bool _keepScreenOn = true;
  bool get keepScreenOn => _keepScreenOn;

  // ---------- 图源 / 语言 ----------
  bool _express = false;
  bool get express => _express;

  String _lang = 'TW';
  String get lang => _lang;

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
      final tm = await _store.getString('theme_mode', 'system');
      _themeMode = switch (tm) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _volumeKeyPaging = await _store.getBool('volume_key_paging', true);
      _readDirection =
          (await _store.getString('read_direction', 'vertical')) == 'horizontal'
              ? ReadDirection.horizontal
              : ReadDirection.vertical;
      _keepScreenOn = await _store.getBool('keep_screen_on', true);
      _express = await _store.getBool('express', false);
      _lang = await _store.getString('lang', 'TW');

      final jwt = await _store.getString('jwt');
      final avs = await _store.getString('avs');
      _c.setAuth(jwt, avs);
      final userMap = await _store.getJson('user');
      if (userMap.isNotEmpty) {
        _user = LoginData.fromMapSafe(userMap);
      }
      _searchHistory = await _store.getSearchHistory();
    } catch (_) {
      // 设置恢复失败不阻塞启动
    }

    // 主机解析 + 拉取全局 setting（img_host 封面图床）
    try {
      await _c.init(language: _lang);
      _ready = true;
      notifyListeners();
      try {
        final setting = await api.getSetting();
        if (setting.imgHost.isNotEmpty) _c.imgHost = setting.imgHost;
        notifyListeners();
      } catch (_) {}
    } catch (e) {
      _initError = e.toString();
      _ready = true;
      notifyListeners();
    }
  }

  // ---------- 设置项写入 ----------

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _store.setString(
        'theme_mode',
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
  }

  Future<void> setVolumeKeyPaging(bool v) async {
    _volumeKeyPaging = v;
    notifyListeners();
    await _store.setBool('volume_key_paging', v);
  }

  Future<void> setReadDirection(ReadDirection d) async {
    _readDirection = d;
    notifyListeners();
    await _store.setString('read_direction',
        d == ReadDirection.horizontal ? 'horizontal' : 'vertical');
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    notifyListeners();
    await _store.setBool('keep_screen_on', v);
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
    try {
      await api.updateSetting(v);
    } catch (_) {}
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
